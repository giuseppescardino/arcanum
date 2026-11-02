import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Keeps the quick-unlock secret behind the platform's biometrics.
abstract class QuickUnlockStore {
  /// Name shown in the UI ("Windows Hello", "Face ID / Touch ID", ...).
  String get methodName;

  Future<bool> isAvailable();
  Future<void> save(String secret);

  /// Asks for biometrics; null if the user cancels or it isn't available.
  Future<String?> read();
  Future<void> delete();
}

/// - iOS/macOS: Keychain item bound to the *current* biometric enrollment
///   through the Secure Enclave; enrolling a new finger/face invalidates it.
/// - Android: Keystore key that requires strong biometrics per use.
/// - Windows: DPAPI-encrypted, released after a Windows Hello check. This is
///   a consent gate, not a hardware binding (documented in SECURITY.md).
class PlatformQuickUnlockStore implements QuickUnlockStore {
  PlatformQuickUnlockStore({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  static const _key = 'pm.quick_unlock';
  static const _reason = 'Sblocca il vault';
  final LocalAuthentication _auth;

  bool get _isApple =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// Platforms where the storage itself shows the biometric prompt.
  bool get _hardwareBound => _isApple || _isAndroid;

  FlutterSecureStorage get _storage {
    const apple = [AccessControlFlag.biometryCurrentSet];
    return FlutterSecureStorage(
      iOptions: const IOSOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
        accessControlFlags: apple,
        useSecureEnclave: true,
      ),
      mOptions: const MacOsOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
        accessControlFlags: apple,
        useSecureEnclave: true,
      ),
      aOptions: const AndroidOptions.biometric(
        enforceBiometrics: true,
        requireBiometricsPerOperation: true,
        biometricType: AndroidBiometricType.strongBiometricOnly,
        resetOnError: false,
        storageNamespace: 'arcanum_quick_unlock',
        biometricPromptTitle: _reason,
      ),
    );
  }

  @override
  String get methodName => switch (defaultTargetPlatform) {
    TargetPlatform.windows => 'Windows Hello',
    TargetPlatform.iOS || TargetPlatform.macOS => 'Face ID / Touch ID',
    _ => 'impronta digitale',
  };

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() &&
          (await _auth.canCheckBiometrics || !_hardwareBound);
    } catch (_) {
      // No plugin, no hardware, or the platform refused: just don't offer it.
      return false;
    }
  }

  @override
  Future<void> save(String secret) async {
    if (!_hardwareBound && !await _confirm()) {
      throw StateError('Verifica annullata');
    }
    await _storage.write(key: _key, value: secret);
  }

  @override
  Future<String?> read() async {
    try {
      if (!_hardwareBound && !await _confirm()) return null;
      return await _storage.read(key: _key);
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: _key);
    } on PlatformException {
      // Already gone or key invalidated by a biometric change.
    }
  }

  Future<bool> _confirm() async {
    try {
      return await _auth.authenticate(localizedReason: _reason);
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }
}
