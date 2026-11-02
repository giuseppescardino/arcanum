import '../src/rust/api/tools.dart' as rust;
import '../src/rust/api/tools.dart'
    show
        PassphraseGeneratorOptions,
        PasswordGeneratorOptions,
        PasswordStrength,
        TotpCode;
import '../src/rust/api/vault.dart' show VaultFailure;

export '../src/rust/api/tools.dart'
    show
        PassphraseGeneratorOptions,
        PasswordGeneratorOptions,
        PasswordStrength,
        PasswordStrengthLevel,
        TotpCode;

/// Generator, strength meter and TOTP. Implemented in Rust; swappable so
/// widget tests can run without the native library.
abstract class Tools {
  String generatePassword(PasswordGeneratorOptions options);
  String generatePassphrase(PassphraseGeneratorOptions options);
  PasswordStrength strength(String password);

  /// Null when [secret] is not a valid TOTP secret or otpauth URI.
  TotpCode? totp(String secret, DateTime now);
  bool isValidTotp(String secret);
}

class RustTools implements Tools {
  const RustTools();

  @override
  String generatePassword(PasswordGeneratorOptions options) =>
      rust.generatePassword(options: options);

  @override
  String generatePassphrase(PassphraseGeneratorOptions options) =>
      rust.generatePassphrase(options: options);

  @override
  PasswordStrength strength(String password) =>
      rust.passwordStrength(password: password);

  @override
  TotpCode? totp(String secret, DateTime now) {
    try {
      return rust.totpCode(
        secret: secret,
        unixSeconds: now.millisecondsSinceEpoch ~/ 1000,
      );
    } on VaultFailure {
      return null;
    }
  }

  @override
  bool isValidTotp(String secret) => rust.isValidTotp(secret: secret);
}

Tools tools = const RustTools();
