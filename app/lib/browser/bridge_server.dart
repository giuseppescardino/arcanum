import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'bridge_clients.dart';
import 'bridge_crypto.dart';
import 'bridge_handler.dart';

const bridgePorts = [47613, 47614, 47615];
const _maxBody = 64 * 1024;
const _pairingWindow = Duration(seconds: 120);
const _replayWindowMs = 60 * 1000;
const _maxCodeAttempts = 3;

enum PairingResult { approved, wrongCode, rejected }

/// A pairing started by a browser: committed first, then revealed. Only a
/// revealed pairing is shown to the user, who must type the browser's
/// code; the app never displays it.
class PendingPairing {
  PendingPairing._(this.id, this.name, this._commit, this._appKey);

  final String id;
  final String name;
  final Uint8List _commit;
  final BridgeAppKey _appKey;
  BridgePairing? _result;
  int _attempts = 0;

  bool get revealed => _result != null;
}

class _HttpError implements Exception {
  _HttpError(this.status, this.code);
  final int status;
  final String code;
}

/// Accepts each request id once within the timestamp window.
class _ReplayGuard {
  final _seen = <String, int>{};

  bool accept(String id, int ts, int now) {
    if ((now - ts).abs() > _replayWindowMs) return false;
    _seen.removeWhere((_, at) => now - at > 2 * _replayWindowMs);
    if (_seen.containsKey(id)) return false;
    _seen[id] = now;
    return true;
  }
}

/// Loopback server for the browser extension (see
/// docs/superpowers/specs/2026-11-11-browser-extension-design.md).
/// Listens on 127.0.0.1 only; every request after pairing is encrypted
/// with the browser's key.
class BridgeServer extends ChangeNotifier {
  BridgeServer({
    required this.handler,
    required this.crypto,
    required this.store,
    this.ports = bridgePorts,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final BridgeHandler handler;
  final BridgeCrypto crypto;
  final BridgeClientStore store;
  final List<int> ports;
  final DateTime Function() _now;
  final _random = Random.secure();

  HttpServer? _server;
  String? _error;
  List<PairedBrowser> _browsers = [];
  final _replay = <String, _ReplayGuard>{};

  DateTime? _pairingUntil;
  PendingPairing? _pending;
  final _finished = <String, Map<String, Object?>>{};
  Timer? _expiryTimer;

  int? get port => _server?.port;

  /// Set when no port could be bound.
  String? get error => _error;
  List<PairedBrowser> get browsers => List.unmodifiable(_browsers);

  bool get pairingOpen {
    final until = _pairingUntil;
    if (until != null && !_now().isBefore(until)) _closePairing();
    return _pairingUntil != null;
  }

  /// The pairing waiting for the user's code, once the browser revealed its key.
  PendingPairing? get pending {
    final p = pairingOpen ? _pending : null;
    return p != null && p.revealed ? p : null;
  }

  Future<void> start() async {
    _browsers = await store.load();
    for (final p in ports) {
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, p);
        break;
      } on SocketException {
        continue;
      }
    }
    final server = _server;
    if (server == null) {
      _error = 'ports_busy';
      notifyListeners();
      return;
    }
    _error = null;
    server.listen(_serve);
    notifyListeners();
  }

  Future<void> stop() async {
    _expiryTimer?.cancel();
    await _server?.close(force: true);
    _server = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  // ---- Pairing, driven by the UI ----

  void openPairing() {
    _finished.clear();
    _pending = null;
    _pairingUntil = _now().add(_pairingWindow);
    _expiryTimer?.cancel();
    _expiryTimer = Timer(_pairingWindow, () {
      if (!pairingOpen) notifyListeners();
    });
    notifyListeners();
  }

  /// Approves the pending pairing if [typedCode] is the browser's code.
  /// After [_maxCodeAttempts] wrong codes the pairing is rejected.
  Future<PairingResult> approve(String typedCode) async {
    final p = pending;
    if (p == null) return PairingResult.rejected;
    final digits = typedCode.replaceAll(RegExp(r'\s'), '');
    if (!_sameCode(digits, p._result!.code)) {
      if (++p._attempts >= _maxCodeAttempts) {
        reject();
        return PairingResult.rejected;
      }
      notifyListeners();
      return PairingResult.wrongCode;
    }
    final browser = PairedBrowser(
      id: _randomId(),
      name: p.name,
      key: p._result!.key,
      created: _now(),
    );
    _browsers = [..._browsers, browser];
    await store.save(_browsers);
    _finished[p.id] = {'state': 'approved', 'client': browser.id};
    _pending = null;
    _pairingUntil = null;
    notifyListeners();
    return PairingResult.approved;
  }

  static bool _sameCode(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  void reject() {
    final p = _pending;
    if (p != null) _finished[p.id] = {'state': 'rejected'};
    _closePairing();
    notifyListeners();
  }

  void _closePairing() {
    _pending = null;
    _pairingUntil = null;
    _expiryTimer?.cancel();
  }

  Future<void> revoke(String id) async {
    _browsers = [
      for (final b in _browsers)
        if (b.id != id) b,
    ];
    _replay.remove(id);
    await store.save(_browsers);
    notifyListeners();
  }

  // ---- HTTP ----

  Future<void> _serve(HttpRequest request) async {
    final res = request.response;
    try {
      final origin = request.headers.value('origin');
      if (origin != null) {
        if (!origin.startsWith('chrome-extension://') &&
            !origin.startsWith('safari-web-extension://')) {
          throw _HttpError(HttpStatus.forbidden, 'forbidden');
        }
        res.headers
          ..set('access-control-allow-origin', origin)
          ..set('vary', 'origin');
      }
      if (request.headers.value(HttpHeaders.hostHeader) !=
          '127.0.0.1:${port ?? 0}') {
        throw _HttpError(HttpStatus.forbidden, 'forbidden');
      }
      if (request.method == 'OPTIONS') {
        res.headers
          ..set('access-control-allow-methods', 'POST')
          ..set('access-control-allow-headers', 'content-type');
        res.statusCode = HttpStatus.noContent;
        return;
      }
      if (request.method != 'POST' || request.uri.path != '/v1') {
        throw _HttpError(HttpStatus.notFound, 'not_found');
      }
      final body = await _readJson(request);
      final reply = await _dispatch(body);
      _write(res, HttpStatus.ok, reply);
    } on _HttpError catch (e) {
      _write(res, e.status, {'error': e.code});
    } catch (e) {
      debugPrint('Browser bridge: $e');
      _write(res, HttpStatus.internalServerError, {'error': 'internal'});
    } finally {
      await res.close();
    }
  }

  static void _write(HttpResponse res, int status, Map<String, Object?> body) {
    try {
      res.statusCode = status;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(body));
    } on StateError {
      // Headers already sent (e.g. the OPTIONS path).
    }
  }

  static Future<Map<String, Object?>> _readJson(HttpRequest request) async {
    if (request.contentLength > _maxBody) {
      throw _HttpError(HttpStatus.requestEntityTooLarge, 'too_large');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request) {
      bytes.add(chunk);
      if (bytes.length > _maxBody) {
        throw _HttpError(HttpStatus.requestEntityTooLarge, 'too_large');
      }
    }
    try {
      final json = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (json is Map) return json.cast<String, Object?>();
    } on FormatException {
      // fall through
    }
    throw _HttpError(HttpStatus.badRequest, 'bad_request');
  }

  static String _field(Map<String, Object?> body, String key) {
    final v = body[key];
    if (v is! String) throw _HttpError(HttpStatus.badRequest, 'bad_request');
    return v;
  }

  Future<Map<String, Object?>> _dispatch(Map<String, Object?> body) async {
    switch (body['type']) {
      case 'hello':
        return {'app': 'arcanum', 'protocol': 1, 'pairing': pairingOpen};
      case 'pair_start':
        return _pairStart(body);
      case 'pair_reveal':
        return _pairReveal(body);
      case 'pair_status':
        final id = _field(body, 'pairing');
        if ((pairingOpen ? _pending : null)?.id == id) {
          return {'state': 'pending'};
        }
        return _finished[id] ?? {'state': 'rejected'};
      case 'msg':
        return _message(body);
      default:
        throw _HttpError(HttpStatus.badRequest, 'bad_request');
    }
  }

  /// Step 1: the browser commits to its key without revealing it.
  Map<String, Object?> _pairStart(Map<String, Object?> body) {
    if (!pairingOpen) throw _HttpError(HttpStatus.forbidden, 'pairing_closed');
    if (_pending != null) throw _HttpError(HttpStatus.conflict, 'pairing_busy');
    final name = _field(body, 'name').trim();
    final Uint8List commit;
    try {
      commit = base64.decode(_field(body, 'commit'));
    } on FormatException {
      throw _HttpError(HttpStatus.badRequest, 'bad_request');
    }
    final appKey = crypto.pairBegin();
    _pending = PendingPairing._(
      _randomId(),
      name.isEmpty ? 'Browser' : name.substring(0, min(name.length, 40)),
      commit,
      appKey,
    );
    return {'pairing': _pending!.id, 'pub': base64.encode(appKey.appPub)};
  }

  /// Step 2: the browser reveals the key it committed to; only now can
  /// either side compute the code.
  Map<String, Object?> _pairReveal(Map<String, Object?> body) {
    final p = pairingOpen ? _pending : null;
    if (p == null || p.revealed || body['pairing'] != p.id) {
      throw _HttpError(HttpStatus.badRequest, 'bad_request');
    }
    try {
      p._result = crypto.pairFinish(
        p._appKey,
        base64.decode(_field(body, 'pub')),
        base64.decode(_field(body, 'nonce')),
        p._commit,
      );
    } catch (_) {
      reject();
      throw _HttpError(HttpStatus.badRequest, 'bad_request');
    }
    notifyListeners();
    return {};
  }

  Future<Map<String, Object?>> _message(Map<String, Object?> body) async {
    final clientId = _field(body, 'client');
    final browser = _browsers.where((b) => b.id == clientId).firstOrNull;
    if (browser == null) {
      throw _HttpError(HttpStatus.unauthorized, 'unknown_client');
    }
    final Map<String, Object?> envelope;
    try {
      final plain = crypto.openRequest(
        browser.key,
        clientId,
        _field(body, 'ct'),
      );
      envelope = (jsonDecode(plain) as Map).cast<String, Object?>();
    } catch (_) {
      throw _HttpError(HttpStatus.badRequest, 'bad_message');
    }
    final id = envelope['id'];
    final ts = envelope['ts'];
    final inner = envelope['body'];
    if (id is! String || ts is! int || inner is! Map) {
      throw _HttpError(HttpStatus.badRequest, 'bad_message');
    }
    final guard = _replay.putIfAbsent(clientId, _ReplayGuard.new);
    if (!guard.accept(id, ts, _now().millisecondsSinceEpoch)) {
      throw _HttpError(HttpStatus.badRequest, 'replay');
    }
    final reply = await handler.handle(inner.cast<String, Object?>());
    return {
      'ct': crypto.sealResponse(
        browser.key,
        clientId,
        jsonEncode({'id': id, 'body': reply}),
      ),
    };
  }

  String _randomId() => base64Url
      .encode(List.generate(16, (_) => _random.nextInt(256)))
      .replaceAll('=', '');
}
