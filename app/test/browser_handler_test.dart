import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/browser/bridge_handler.dart';
import 'package:arcanum/src/rust/api/vault.dart';

import 'fake_tools.dart';
import 'fakes.dart';

void main() {
  late FakeVaultHandle handle;
  late VaultController controller;
  late FakeTools tools;
  late BridgeHandler handler;
  late int shown;

  setUp(() async {
    handle = FakeVaultHandle();
    controller = VaultController(
      handle: handle,
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: FakeQuickUnlockStore(available: false),
    );
    tools = FakeTools();
    shown = 0;
    handler = BridgeHandler(
      controller: controller,
      tools: tools,
      showApp: () async => shown++,
    );
    await controller.create('master-password');
    controller.confirmEmergencyKit();
  });

  tearDown(() => controller.dispose());

  Future<String> add(
    String title, {
    List<String> urls = const [],
    String username = 'alice',
    String password = 'pw',
  }) async {
    await controller.save(
      login(title, urls: urls, username: username, password: password),
    );
    return controller.items.firstWhere((i) => i.fields.title == title).id;
  }

  test('status reports locked and unlocked', () async {
    expect(await handler.handle({'op': 'status'}), {'locked': false});
    controller.lock();
    expect(await handler.handle({'op': 'status'}), {'locked': true});
  });

  test('list returns only matching logins, without passwords', () async {
    await add('Example', urls: ['https://example.com']);
    await add('Accounts', urls: ['accounts.example.com']);
    await add('Evil', urls: ['https://evil-example.com']);
    final r = await handler.handle({
      'op': 'list',
      'url': 'https://www.example.com/login',
    });
    final logins = (r['logins'] as List).cast<Map<String, Object?>>();
    expect(
      logins.map((l) => l['title']),
      unorderedEquals(['Example', 'Accounts']),
    );
    expect(logins.first.keys, unorderedEquals(['id', 'title', 'username']));
  });

  test('list ignores the port', () async {
    await add('Dev', urls: ['localhost']);
    final r = await handler.handle({
      'op': 'list',
      'url': 'http://localhost:3000/',
    });
    expect((r['logins'] as List).length, 1);
  });

  test('list for a non-http url is empty', () async {
    await add('Settings', urls: ['settings']);
    final r = await handler.handle({'op': 'list', 'url': 'chrome://settings'});
    expect(r['logins'], isEmpty);
  });

  test('fill returns credentials for a matching site', () async {
    final id = await add('Example', urls: ['example.com'], password: 'secret');
    final r = await handler.handle({
      'op': 'fill',
      'id': id,
      'url': 'https://example.com/',
    });
    expect(r, {'username': 'alice', 'password': 'secret'});
  });

  test('fill on another site is refused', () async {
    final id = await add('Example', urls: ['example.com']);
    final r = await handler.handle({
      'op': 'fill',
      'id': id,
      'url': 'https://evil-example.com/',
    });
    expect(r, {'error': 'domain_mismatch'});
  });

  test('fill of an unknown id is not_found', () async {
    final r = await handler.handle({
      'op': 'fill',
      'id': 'nope',
      'url': 'https://example.com/',
    });
    expect(r, {'error': 'not_found'});
  });

  test('check reports new, update and same', () async {
    final id = await add('Example', urls: ['example.com'], password: 'old');
    Future<Map<String, Object?>> check(String user, String pw) =>
        handler.handle({
          'op': 'check',
          'url': 'https://example.com/',
          'username': user,
          'password': pw,
        });
    expect(await check('bob', 'x'), {'state': 'new'});
    expect(await check(' alice ', 'new'), {'state': 'update', 'id': id});
    expect(await check('alice', 'old'), {'state': 'same'});
  });

  test('empty username is new and can be saved', () async {
    final r = await handler.handle({
      'op': 'check',
      'url': 'https://example.com/',
      'username': '',
      'password': 'pw',
    });
    expect(r, {'state': 'new'});
    final saved = await handler.handle({
      'op': 'save',
      'url': 'https://example.com/',
      'username': '',
      'password': 'pw',
    });
    expect(saved['id'], isA<String>());
    expect(controller.items.single.fields.username, '');
  });

  test('save creates a login titled with the host', () async {
    final r = await handler.handle({
      'op': 'save',
      'url': 'https://www.example.com/signup?x=1',
      'username': 'bob',
      'password': 'pw1',
    });
    final item = controller.items.single;
    expect(r, {'id': item.id});
    expect(item.fields.kind, VaultItemKind.login);
    expect(item.fields.title, 'example.com');
    expect(item.fields.urls, ['https://example.com']);
    expect(item.fields.username, 'bob');
    expect(item.fields.password, 'pw1');
  });

  test('save for a non-http url is a bad request', () async {
    final r = await handler.handle({
      'op': 'save',
      'url': 'about:blank',
      'username': 'bob',
      'password': 'pw',
    });
    expect(r, {'error': 'bad_request'});
    expect(controller.items, isEmpty);
  });

  test('update changes the password only on a matching site', () async {
    final id = await add('Example', urls: ['example.com'], password: 'old');
    expect(
      await handler.handle({
        'op': 'update',
        'id': id,
        'url': 'https://evil.com/',
        'password': 'new',
      }),
      {'error': 'domain_mismatch'},
    );
    expect(
      await handler.handle({
        'op': 'update',
        'id': id,
        'url': 'https://example.com/',
        'password': 'new',
      }),
      <String, Object?>{},
    );
    final f = controller.items.single.fields;
    expect(f.password, 'new');
    expect(f.title, 'Example');
    expect(f.username, 'alice');
  });

  test('a locked vault refuses list, fill, check, save and update', () async {
    final id = await add('Example', urls: ['example.com']);
    controller.lock();
    for (final body in <Map<String, Object?>>[
      {'op': 'list', 'url': 'https://example.com'},
      {'op': 'fill', 'id': id, 'url': 'https://example.com'},
      {
        'op': 'check',
        'url': 'https://example.com',
        'username': 'a',
        'password': 'b',
      },
      {
        'op': 'save',
        'url': 'https://example.com',
        'username': 'a',
        'password': 'b',
      },
      {'op': 'update', 'id': id, 'url': 'https://example.com', 'password': 'b'},
    ]) {
      expect(await handler.handle(body), {'error': 'locked'}, reason: '$body');
    }
  });

  test('generate uses the spec options', () async {
    final r = await handler.handle({'op': 'generate'});
    expect((r['password'] as String).length, 20);
  });

  test('open_app shows the app', () async {
    expect(await handler.handle({'op': 'open_app'}), <String, Object?>{});
    expect(shown, 1);
  });

  test('unknown op or missing fields is a bad request', () async {
    expect(await handler.handle({'op': 'nope'}), {'error': 'bad_request'});
    expect(await handler.handle({'op': 'fill'}), {'error': 'bad_request'});
  });
}
