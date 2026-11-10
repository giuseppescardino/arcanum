import 'dart:io';

import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';

String failureMessage(Object error) {
  if (error is VaultFailure) {
    return switch (error.code) {
      VaultFailureCode.wrongCredentials => l10n.errorWrongCredentials,
      VaultFailureCode.invalidSecretKey => l10n.errorInvalidSecretKey,
      VaultFailureCode.locked => l10n.errorLocked,
      VaultFailureCode.notInitialized => l10n.errorNotInitialized,
      VaultFailureCode.alreadyInitialized => l10n.errorAlreadyInitialized,
      VaultFailureCode.notFound => l10n.errorNotFound,
      VaultFailureCode.invalidLogin => l10n.errorInvalidLogin,
      VaultFailureCode.accountExists => l10n.errorAccountExists,
      VaultFailureCode.inviteRequired => l10n.errorInviteRequired,
      VaultFailureCode.invalidInvite => l10n.errorInvalidInvite,
      VaultFailureCode.registrationClosed => l10n.errorRegistrationClosed,
      VaultFailureCode.quotaExceeded => l10n.errorQuotaExceeded,
      VaultFailureCode.sessionExpired => l10n.errorSessionExpired,
      VaultFailureCode.tooManyRequests => l10n.errorTooManyRequests,
      VaultFailureCode.invalidServerUrl => l10n.errorInvalidServerUrl,
      VaultFailureCode.network => l10n.errorNetwork,
      VaultFailureCode.notLinked => l10n.errorNotLinked,
      VaultFailureCode.invalidInput => l10n.errorInvalidInput(error.message),
      VaultFailureCode.passwordRequired => l10n.errorPasswordRequired,
      VaultFailureCode.unsupportedFormat => l10n.errorUnsupportedFormat,
      VaultFailureCode.backupPasswordRequired =>
        l10n.errorBackupPasswordRequired,
      VaultFailureCode.internal => l10n.errorInternal(error.message),
    };
  }
  if (error is StateError) return error.message;
  if (error is FileSystemException) return l10n.errorFile(error.message);
  return l10n.errorUnexpected('$error');
}
