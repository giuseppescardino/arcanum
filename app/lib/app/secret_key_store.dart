import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the Secret Key in the platform keychain (Keychain on Apple,
/// Keystore-backed storage on Android, DPAPI on Windows, the Secret Service
/// via libsecret on Linux), so the user only types it once per device. Never synced to iCloud Keychain.
class SecretKeyStore {
  SecretKeyStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  static const _key = 'pm.secret_key';
  final FlutterSecureStorage _storage;

  Future<String?> read() => _storage.read(key: _key);

  Future<void> write(String secretKey) =>
      _storage.write(key: _key, value: secretKey);

  Future<void> delete() => _storage.delete(key: _key);
}
