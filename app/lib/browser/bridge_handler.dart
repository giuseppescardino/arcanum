import '../app/item_fields.dart';
import '../app/tools.dart';
import '../app/vault_controller.dart';
import '../autofill/matching.dart';
import '../src/rust/api/vault.dart';

/// Password suggested to the browser for new accounts.
const browserGeneratorOptions = PasswordGeneratorOptions(
  length: 20,
  lowercase: true,
  uppercase: true,
  digits: true,
  symbols: true,
  avoidAmbiguous: false,
);

/// Host of an http(s) page URL, without `www.` and port; null otherwise.
String? pageHost(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return null;
  return host.startsWith('www.') ? host.substring(4) : host;
}

class _BadRequest implements Exception {}

/// Executes decrypted browser requests against the vault. Every URL here
/// is the tab URL the extension's background read from the browser.
class BridgeHandler {
  BridgeHandler({
    required this.controller,
    required this.tools,
    required this.showApp,
  });

  final VaultController controller;
  final Tools tools;
  final Future<void> Function() showApp;

  static const _needsUnlock = {'list', 'fill', 'check', 'save', 'update'};

  /// Ops that follow a click in the extension's own UI. Only these count
  /// as activity: a page can trigger list/check by itself and must not be
  /// able to keep the vault from locking.
  static const _userActions = {'fill', 'save', 'update'};

  Future<Map<String, Object?>> handle(Map<String, Object?> body) async {
    final op = body['op'];
    try {
      if (_needsUnlock.contains(op)) {
        if (controller.stage != VaultStage.unlocked) {
          return {'error': 'locked'};
        }
        if (_userActions.contains(op)) controller.touch();
      }
      switch (op) {
        case 'status':
          return {'locked': controller.stage != VaultStage.unlocked};
        case 'open_app':
          await showApp();
          return {};
        case 'generate':
          return {'password': tools.generatePassword(browserGeneratorOptions)};
        case 'list':
          final host = pageHost(_str(body, 'url'));
          return {
            'logins': [
              if (host != null)
                for (final i in _matching(host))
                  {
                    'id': i.id,
                    'title': i.fields.title,
                    'username': i.fields.username,
                  },
            ],
          };
        case 'fill':
          final item = _find(_str(body, 'id'));
          if (item == null) return {'error': 'not_found'};
          if (!_matches(item, _str(body, 'url'))) {
            return {'error': 'domain_mismatch'};
          }
          return {
            'username': item.fields.username,
            'password': item.fields.password,
          };
        case 'check':
          final host = pageHost(_str(body, 'url'));
          if (host == null) return {'error': 'bad_request'};
          final username = _str(body, 'username').trim().toLowerCase();
          final password = _str(body, 'password');
          final matching = _matching(host).toList();
          if (username.isEmpty) {
            // Two-step logins submit the password without the username.
            if (matching.any((i) => i.fields.password == password)) {
              return {'state': 'same'};
            }
            if (matching.length == 1) {
              return {'state': 'update', 'id': matching.single.id};
            }
            return {'state': 'new'};
          }
          for (final i in matching) {
            if (i.fields.username.trim().toLowerCase() != username) continue;
            return i.fields.password == password
                ? {'state': 'same'}
                : {'state': 'update', 'id': i.id};
          }
          return {'state': 'new'};
        case 'save':
          final host = pageHost(_str(body, 'url'));
          if (host == null) return {'error': 'bad_request'};
          final before = controller.items.map((i) => i.id).toSet();
          await controller.save(
            ItemFields(
              kind: VaultItemKind.login,
              title: host,
              username: _str(body, 'username').trim(),
              password: _str(body, 'password'),
              urls: ['https://$host'],
              notes: '',
              favorite: false,
              group: '',
            ),
          );
          final added = controller.items.where((i) => !before.contains(i.id));
          return {'id': added.isEmpty ? null : added.first.id};
        case 'update':
          final item = _find(_str(body, 'id'));
          if (item == null) return {'error': 'not_found'};
          if (!_matches(item, _str(body, 'url'))) {
            return {'error': 'domain_mismatch'};
          }
          final f = item.fields;
          await controller.save(
            f.copyWith(password: _str(body, 'password')),
            id: item.id,
          );
          return {};
        default:
          return {'error': 'bad_request'};
      }
    } on _BadRequest {
      return {'error': 'bad_request'};
    } on VaultFailure catch (e) {
      return {
        'error': e.code == VaultFailureCode.locked ? 'locked' : 'internal',
      };
    }
  }

  static String _str(Map<String, Object?> body, String key) {
    final v = body[key];
    if (v is! String) throw _BadRequest();
    return v;
  }

  VaultItem? _find(String id) {
    for (final i in controller.items) {
      if (i.id == id) return i;
    }
    return null;
  }

  Iterable<VaultItem> _matching(String host) => controller.items.where(
    (i) =>
        i.fields.kind == VaultItemKind.login &&
        i.fields.urls
            .map(hostOf)
            .whereType<String>()
            .any((h) => hostsMatch(h, host)),
  );

  bool _matches(VaultItem item, String url) {
    final host = pageHost(url);
    return host != null && _matching(host).any((i) => i.id == item.id);
  }
}
