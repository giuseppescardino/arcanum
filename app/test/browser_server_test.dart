import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/browser/bridge_handler.dart';
import 'package:arcanum/browser/bridge_server.dart';

import 'fake_tools.dart';
import 'fakes.dart';

const extOrigin = 'chrome-extension://abcdefghijklmnop';

void main() {
  late VaultController controller;
  late MemoryBridgeClientStore store;
  late BridgeServer server;
  late DateTime now;

  BridgeServer make({List<int> ports = const [0]}) => BridgeServer(
    handler: BridgeHandler(
      controller: controller,
      tools: FakeTools(),
      showApp: () async {},
    ),
    crypto: FakeBridgeCrypto(),
    store: store,
    ports: ports,
    now: () => now,
  );

  // The test binding replaces HttpClient with one that always answers
  // 400; these tests need real loopback requests.
  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    now = DateTime(2026, 11, 11, 12);
    controller = VaultController(
      handle: FakeVaultHandle(),
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: FakeQuickUnlockStore(available: false),
    );
    await controller.create('master-password');
    controller.confirmEmergencyKit();
    store = MemoryBridgeClientStore();
    server = make();
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    controller.dispose();
  });

  Future<(int, Map<String, Object?>, HttpHeaders)> post(
    Object body, {
    String? origin = extOrigin,
    String? host,
    int? port,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.post('127.0.0.1', port ?? server.port!, '/v1');
      if (host != null) req.headers.set(HttpHeaders.hostHeader, host);
      if (origin != null) req.headers.set('origin', origin);
      req.headers.contentType = ContentType.json;
      req.add(
        body is String ? utf8.encode(body) : utf8.encode(jsonEncode(body)),
      );
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      final json = text.isEmpty
          ? <String, Object?>{}
          : (jsonDecode(text) as Map).cast<String, Object?>();
      return (res.statusCode, json, res.headers);
    } finally {
      client.close(force: true);
    }
  }

  final extPub = base64.encode(List.filled(32, 3));

  Future<String> pairBrowser() async {
    server.openPairing();
    final (_, start, _) = await post({
      'type': 'pair_start',
      'name': 'Chrome',
      'pub': extPub,
    });
    await server.approve();
    final (_, status, _) = await post({
      'type': 'pair_status',
      'pairing': start['pairing'],
    });
    return status['client'] as String;
  }

  var seq = 0;
  Map<String, Object?> encrypted(
    String client,
    Map<String, Object?> body, {
    String? id,
    int? ts,
  }) => {
    'type': 'msg',
    'client': client,
    'ct': FakeBridgeCrypto.seal(
      client,
      'req',
      jsonEncode({
        'id': id ?? 'req-${seq++}',
        'ts': ts ?? now.millisecondsSinceEpoch,
        'body': body,
      }),
    ),
  };

  Map<String, Object?> decrypt(String client, Map<String, Object?> res) =>
      (jsonDecode(
        FakeBridgeCrypto.open(client, 'res', res['ct'] as String),
      ) as Map).cast<String, Object?>();

  test('binds the next port when the first is taken', () async {
    final squatter = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final other = make(ports: [squatter.port, 0]);
    await other.start();
    expect(other.port, isNot(squatter.port));
    expect(other.port, isNotNull);
    expect(other.error, isNull);
    await other.stop();
    await squatter.close();
  });

  test('reports an error when every port is taken', () async {
    final squatter = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final other = make(ports: [squatter.port]);
    await other.start();
    expect(other.port, isNull);
    expect(other.error, isNotNull);
    await squatter.close();
  });

  test('rejects a web origin', () async {
    final (status, _, _) = await post({
      'type': 'hello',
    }, origin: 'https://evil.com');
    expect(status, 403);
  });

  test('rejects a foreign Host header', () async {
    final (status, _, _) = await post({
      'type': 'hello',
    }, host: 'evil.com:${server.port}');
    expect(status, 403);
  });

  test('rejects an oversized body', () async {
    final (status, _, _) = await post('x' * (64 * 1024 + 1));
    expect(status, 413);
  });

  test('hello reports the pairing state', () async {
    var (status, body, _) = await post({'type': 'hello'}, origin: null);
    expect(status, 200);
    expect(body, {'app': 'arcanum', 'protocol': 1, 'pairing': false});
    server.openPairing();
    (_, body, _) = await post({'type': 'hello'});
    expect(body['pairing'], true);
  });

  test('extension origin gets a CORS header', () async {
    final (_, _, headers) = await post({'type': 'hello'});
    expect(headers.value('access-control-allow-origin'), extOrigin);
  });

  test('pair_start is refused while pairing is closed', () async {
    final (status, body, _) = await post({
      'type': 'pair_start',
      'name': 'Chrome',
      'pub': extPub,
    });
    expect(status, 403);
    expect(body, {'error': 'pairing_closed'});
  });

  test('pairing flow: approve', () async {
    server.openPairing();
    final (status, start, _) = await post({
      'type': 'pair_start',
      'name': 'Chrome',
      'pub': extPub,
    });
    expect(status, 200);
    expect(start['pub'], base64.encode(List.filled(32, 9)));
    expect(server.pending?.code, '123456');
    expect(server.pending?.name, 'Chrome');

    var (_, st, _) = await post({
      'type': 'pair_status',
      'pairing': start['pairing'],
    });
    expect(st, {'state': 'pending'});

    await server.approve();
    (_, st, _) = await post({
      'type': 'pair_status',
      'pairing': start['pairing'],
    });
    expect(st['state'], 'approved');
    expect(st['client'], isA<String>());
    expect(server.pending, isNull);
    expect(store.saved.single.name, 'Chrome');
    expect(store.saved.single.key, Uint8List.fromList(List.filled(32, 3)));
    expect(server.browsers.single.id, st['client']);
  });

  test('a second pair_start is busy', () async {
    server.openPairing();
    await post({'type': 'pair_start', 'name': 'Chrome', 'pub': extPub});
    final (status, body, _) = await post({
      'type': 'pair_start',
      'name': 'Opera',
      'pub': extPub,
    });
    expect(status, 409);
    expect(body, {'error': 'pairing_busy'});
  });

  test('a bad public key is a bad request', () async {
    server.openPairing();
    final (status, _, _) = await post({
      'type': 'pair_start',
      'name': 'Chrome',
      'pub': base64.encode([1, 2, 3]),
    });
    expect(status, 400);
    expect(server.pending, isNull);
  });

  test('pairing expires after 120 s', () async {
    server.openPairing();
    final (_, start, _) = await post({
      'type': 'pair_start',
      'name': 'Chrome',
      'pub': extPub,
    });
    now = now.add(const Duration(seconds: 121));
    expect(server.pending, isNull);
    final (_, st, _) = await post({
      'type': 'pair_status',
      'pairing': start['pairing'],
    });
    expect(st, {'state': 'rejected'});
    final (status, _, _) = await post({
      'type': 'pair_start',
      'name': 'Chrome',
      'pub': extPub,
    });
    expect(status, 403);
  });

  test('reject reports rejected', () async {
    server.openPairing();
    final (_, start, _) = await post({
      'type': 'pair_start',
      'name': 'Chrome',
      'pub': extPub,
    });
    server.reject();
    final (_, st, _) = await post({
      'type': 'pair_status',
      'pairing': start['pairing'],
    });
    expect(st, {'state': 'rejected'});
    expect(store.saved, isEmpty);
  });

  test('encrypted status round trip echoes the request id', () async {
    final client = await pairBrowser();
    final (status, res, _) = await post(
      encrypted(client, {'op': 'status'}, id: 'abc'),
    );
    expect(status, 200);
    expect(decrypt(client, res), {
      'id': 'abc',
      'body': {'locked': false},
    });
  });

  test('a replayed request is rejected', () async {
    final client = await pairBrowser();
    final msg = encrypted(client, {'op': 'status'});
    expect((await post(msg)).$1, 200);
    final (status, body, _) = await post(msg);
    expect(status, 400);
    expect(body, {'error': 'replay'});
  });

  test('a stale request is rejected', () async {
    final client = await pairBrowser();
    final (status, _, _) = await post(
      encrypted(client, {
        'op': 'status',
      }, ts: now.millisecondsSinceEpoch - 61000),
    );
    expect(status, 400);
  });

  test('a forged ciphertext is rejected', () async {
    final client = await pairBrowser();
    final (status, _, _) = await post({
      'type': 'msg',
      'client': client,
      'ct': FakeBridgeCrypto.seal(client, 'res', '{}'),
    });
    expect(status, 400);
  });

  test('an unknown client gets 401', () async {
    final (status, body, _) = await post(encrypted('nobody', {'op': 'status'}));
    expect(status, 401);
    expect(body, {'error': 'unknown_client'});
  });

  test('revoke makes the client unknown', () async {
    final client = await pairBrowser();
    await server.revoke(client);
    expect(store.saved, isEmpty);
    final (status, _, _) = await post(encrypted(client, {'op': 'status'}));
    expect(status, 401);
  });

  test('paired browsers survive a restart', () async {
    final client = await pairBrowser();
    await server.stop();
    server = make();
    await server.start();
    expect(server.browsers.single.id, client);
    final (status, _, _) = await post(encrypted(client, {'op': 'status'}));
    expect(status, 200);
  });

  test('malformed JSON is a bad request', () async {
    final (status, _, _) = await post('{nope');
    expect(status, 400);
  });
}
