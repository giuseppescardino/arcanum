import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A browser paired with the app, holding its message key.
class PairedBrowser {
  const PairedBrowser({
    required this.id,
    required this.name,
    required this.key,
    required this.created,
  });

  final String id;
  final String name;
  final Uint8List key;
  final DateTime created;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'key': base64.encode(key),
    'created': created.millisecondsSinceEpoch,
  };

  static PairedBrowser fromJson(Map<String, Object?> json) => PairedBrowser(
    id: json['id'] as String,
    name: json['name'] as String,
    key: base64.decode(json['key'] as String),
    created: DateTime.fromMillisecondsSinceEpoch(json['created'] as int),
  );
}

abstract class BridgeClientStore {
  Future<List<PairedBrowser>> load();
  Future<void> save(List<PairedBrowser> browsers);
}

/// Paired browsers in the system keychain, never synced.
class SecureBridgeClientStore implements BridgeClientStore {
  SecureBridgeClientStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  static const _key = 'pm.browser_clients';
  final FlutterSecureStorage _storage;

  @override
  Future<List<PairedBrowser>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          PairedBrowser.fromJson((e as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> save(List<PairedBrowser> browsers) => _storage.write(
    key: _key,
    value: jsonEncode([for (final b in browsers) b.toJson()]),
  );
}
