import 'package:arcanum/app/tools.dart';

/// Deterministic stand-in for the Rust tools.
class FakeTools implements Tools {
  int generated = 0;

  @override
  String generatePassword(PasswordGeneratorOptions options) =>
      'P${++generated}'.padRight(options.length, 'x');

  @override
  String generatePassphrase(PassphraseGeneratorOptions options) =>
      List.filled(options.words, 'word${++generated}').join(options.separator);

  @override
  PasswordStrength strength(String password) => PasswordStrength(
    bits: password.length * 4,
    level: password.length >= 16
        ? PasswordStrengthLevel.strong
        : PasswordStrengthLevel.weak,
  );

  @override
  TotpCode? totp(String secret, DateTime now) => isValidTotp(secret)
      ? TotpCode(code: '123456', period: 30, remaining: 30 - now.second % 30)
      : null;

  @override
  bool isValidTotp(String secret) => secret.startsWith('JBSW');
}
