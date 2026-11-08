// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get cancel => 'Cancel';

  @override
  String get copy => 'Copy';

  @override
  String get delete => 'Delete';

  @override
  String get password => 'Password';

  @override
  String get masterPassword => 'Master password';

  @override
  String get secretKey => 'Secret Key';

  @override
  String get reconnect => 'Reconnect';

  @override
  String get syncTitle => 'Sync';

  @override
  String get syncNow => 'Sync now';

  @override
  String get noGroup => 'No group';

  @override
  String get untitled => '(untitled)';

  @override
  String get username => 'Username';

  @override
  String get passwordsDontMatch => 'Passwords do not match';

  @override
  String get show => 'Show';

  @override
  String get hide => 'Hide';

  @override
  String vaultPasswordOf(String title) {
    return 'Password for \"$title\"';
  }

  @override
  String vaultDeleteGroupTitle(String group) {
    return 'Delete group \"$group\"?';
  }

  @override
  String get vaultDeleteGroupBody =>
      'Items are not deleted: they move to \"No group\".';

  @override
  String get vaultDeleteGroup => 'Delete group';

  @override
  String get vaultForgetSecretKeyTitle => 'Remove the Secret Key?';

  @override
  String get vaultForgetSecretKeyBody =>
      'Next time you unlock on this device you will need the Secret Key from your Emergency Kit. Make sure you have it.';

  @override
  String get vaultRemove => 'Remove';

  @override
  String get vaultTitle => 'Vault';

  @override
  String get vaultLock => 'Lock';

  @override
  String vaultEnableQuickUnlock(String method) {
    return 'Enable unlock with $method';
  }

  @override
  String vaultDisableQuickUnlock(String method) {
    return 'Disable unlock with $method';
  }

  @override
  String get vaultEnableAutofill => 'Enable autofill';

  @override
  String get vaultChangeMasterPassword => 'Change master password';

  @override
  String get vaultAbout => 'About';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutDescription =>
      'Zero-knowledge password manager: your data is encrypted on this device before it is synced.';

  @override
  String get vaultForgetSecretKey => 'Remove Secret Key from this device';

  @override
  String get vaultSignOut => 'Sign out of this device';

  @override
  String get vaultSignOutTitle => 'Sign out?';

  @override
  String get vaultSignOutBodySynced =>
      'The vault will be erased from this device, together with its Secret Key. Your data stays on the sync server: to use it again, sign in with your master password and the Secret Key from your Emergency Kit.';

  @override
  String get vaultSignOutBodyLocal =>
      'This vault is not synced to a server: signing out permanently erases all its items from this device. This cannot be undone.';

  @override
  String get vaultSignOutSyncFailed =>
      'Last sync failed, so recent changes may not be on the server and would be lost. Sign out anyway?';

  @override
  String get vaultSignOutConfirm => 'Sign out';

  @override
  String get vaultSearchHint => 'Search · Enter copies the password';

  @override
  String vaultSearchHintWithShortcut(String shortcut) {
    return 'Search · Enter copies the password · $shortcut from anywhere';
  }

  @override
  String get vaultNew => 'New';

  @override
  String get vaultSessionExpired =>
      'Sync is paused: this device needs to reconnect to the server.';

  @override
  String get vaultAllGroups => 'All';

  @override
  String get vaultGroupActions => 'Group actions';

  @override
  String get vaultRenameGroup => 'Rename group';

  @override
  String get vaultGroupName => 'Name';

  @override
  String get vaultGroupMergeHint =>
      'The group already exists: items will be merged.';

  @override
  String get vaultRename => 'Rename';

  @override
  String get vaultCopyTotp => 'Copy 2FA code';

  @override
  String get vaultTotpCode => '2FA code';

  @override
  String get vaultCopyUsername => 'Copy username';

  @override
  String get vaultCopyPassword => 'Copy password';

  @override
  String get vaultNoResults => 'No results.';

  @override
  String get vaultEmpty =>
      'Your vault is empty.\nAdd your first password with \"New\".';

  @override
  String get vaultMasterPasswordChanged => 'Master password updated.';

  @override
  String get vaultCurrentPassword => 'Current password';

  @override
  String get vaultRequired => 'Required';

  @override
  String get vaultNewPassword => 'New password';

  @override
  String vaultMinLength(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'At least $count characters',
      one: 'At least 1 character',
    );
    return '$_temp0';
  }

  @override
  String get vaultRepeatNewPassword => 'Repeat new password';

  @override
  String get vaultChange => 'Change';

  @override
  String get editorDeleteTitle => 'Delete this item?';

  @override
  String get editorDeleteBody => 'This can\'t be undone.';

  @override
  String get editorNewTitle => 'New item';

  @override
  String get editorEditTitle => 'Edit';

  @override
  String get editorRemoveFavorite => 'Remove from favorites';

  @override
  String get editorFavorite => 'Favorite';

  @override
  String get editorSave => 'Save';

  @override
  String get editorKindLogin => 'Login';

  @override
  String get editorKindSecureNote => 'Secure note';

  @override
  String get editorTitleLabel => 'Title';

  @override
  String get editorTitleRequired => 'Title is required';

  @override
  String get editorUsernameLabel => 'Username / email';

  @override
  String get editorGenerate => 'Generate';

  @override
  String get editorWebsites => 'Websites';

  @override
  String get editorWebsitesHelper => 'One per line';

  @override
  String get editorTotpLabel => '2FA key (TOTP)';

  @override
  String get editorTotpHelper => 'Secret key or otpauth:// URI from the site';

  @override
  String get editorTotpInvalid => 'Invalid 2FA key';

  @override
  String get editorNotes => 'Notes';

  @override
  String get editorGroup => 'Group';

  @override
  String get editorGroupHelper => 'Pick an existing one or type a new one';

  @override
  String get totpCopyCode => 'Copy code';

  @override
  String get totpCode => '2FA code';

  @override
  String get strengthVeryWeak => 'Very weak';

  @override
  String get strengthWeak => 'Weak';

  @override
  String get strengthFair => 'Fair';

  @override
  String get strengthStrong => 'Strong';

  @override
  String get strengthVeryStrong => 'Very strong';

  @override
  String strengthLabelWithBits(String label, int bits) {
    return '$label · $bits bit';
  }

  @override
  String get syncDisconnectTitle => 'Disconnect this device?';

  @override
  String get syncDisconnectBody =>
      'The vault stays on this device but stops syncing. Data on the server and on your other devices is not touched.';

  @override
  String get syncDisconnect => 'Disconnect';

  @override
  String get syncActive => 'Sync is on';

  @override
  String syncServer(String url) {
    return 'Server: $url';
  }

  @override
  String get syncNotYetSynced => 'Not synced yet in this session.';

  @override
  String syncLastSync(String time) {
    return 'Last synced: $time';
  }

  @override
  String syncLastSyncSummary(String time, int pulled, int pushed) {
    return 'Last synced: $time ($pulled received, $pushed sent)';
  }

  @override
  String syncLastSyncSummaryConflicts(
    String time,
    int pulled,
    int pushed,
    int conflicts,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      conflicts,
      locale: localeName,
      other: '$conflicts conflicts',
      one: '1 conflict',
    );
    return 'Last synced: $time ($pulled received, $pushed sent, $_temp0)';
  }

  @override
  String get syncDisconnectDevice => 'Disconnect this device';

  @override
  String get syncEncryptionNote =>
      'Data is encrypted on this device before it is sent: the server only stores unreadable data and knows neither your master password nor your Secret Key.';

  @override
  String get syncEnableTitle => 'Sync across your devices';

  @override
  String get syncEnableBody =>
      'Create an account on your sync server. Everything is encrypted here before it leaves: the server only sees unreadable data. On your other devices choose \"I already have an account\".';

  @override
  String get syncConfirmMasterPassword => 'Master password (to confirm)';

  @override
  String get syncEnable => 'Turn on sync';

  @override
  String get syncReconnectTitle => 'Reconnect this device';

  @override
  String get syncReconnectBody =>
      'Enter the account\'s current master password. If you changed it on another device, use the new one: from now on it applies here too.';

  @override
  String get signInTitle => 'Sign in';

  @override
  String get signInIntro =>
      'Connect this device to your account. You need the Secret Key from your Emergency Kit and your master password.';

  @override
  String get unlockTitle => 'Unlock the vault';

  @override
  String get unlockButton => 'Unlock';

  @override
  String unlockWithMethod(String method) {
    return 'Unlock with $method';
  }

  @override
  String get unlockEnterSecretKeyManually => 'Enter the Secret Key manually';

  @override
  String get setupTitle => 'Create your vault';

  @override
  String get setupIntro =>
      'Your master password encrypts all your data on the device. Nobody, not even us, can recover it: make it long and memorable.';

  @override
  String setupMinLength(int count) {
    return 'At least $count characters';
  }

  @override
  String get setupRepeatMasterPassword => 'Repeat master password';

  @override
  String get setupCreate => 'Create vault';

  @override
  String get setupHaveAccount => 'I already have an account: sign in';

  @override
  String get kitTitle => 'Your Secret Key';

  @override
  String get kitIntro =>
      'Together with your master password, the Secret Key is needed to open the vault on a new device or after reinstalling. It is saved in this device\'s keychain, but if you lose the device without having written it down, your data cannot be recovered.';

  @override
  String get kitWriteItDown =>
      'Write it on paper or store it somewhere safe, away from your master password.';

  @override
  String get kitSavedConfirm => 'I have saved the Secret Key somewhere safe';

  @override
  String get kitContinue => 'Continue';

  @override
  String get commonEnterMasterPassword => 'Enter your master password';

  @override
  String get commonInvalidSecretKey => 'Invalid Secret Key';

  @override
  String get commonSyncServer => 'Sync server';

  @override
  String get commonSyncServerHint => 'https://sync.example.com';

  @override
  String get commonSyncServerInvalid =>
      'Full address, e.g. https://sync.example.com';

  @override
  String get commonInviteCode => 'Invite code';

  @override
  String get commonInviteCodeHelper => 'Only if your server requires one';

  @override
  String get generatorTitle => 'Generate password';

  @override
  String get generatorPassphrase => 'Passphrase';

  @override
  String get generatorRegenerate => 'Regenerate';

  @override
  String get generatorUse => 'Use';

  @override
  String get generatorLength => 'Length';

  @override
  String get generatorLowercase => 'Lowercase (a-z)';

  @override
  String get generatorUppercase => 'Uppercase (A-Z)';

  @override
  String get generatorDigits => 'Numbers (0-9)';

  @override
  String get generatorSymbols => 'Symbols (!@#…)';

  @override
  String get generatorAvoidAmbiguous =>
      'Avoid ambiguous characters (l, 1, O, 0…)';

  @override
  String get generatorWords => 'Words';

  @override
  String get generatorSeparator => 'Separator';

  @override
  String get generatorSeparatorSpace => 'space';

  @override
  String get generatorCapitalize => 'Capitalize words';

  @override
  String get generatorIncludeNumber => 'Add a number';

  @override
  String get autofillNoVault =>
      'There is no vault on this device yet. Open Arcanum to create one or sign in to your account.';

  @override
  String get autofillClose => 'Close';

  @override
  String get autofillDifferentSiteTitle => 'Different site';

  @override
  String autofillDifferentSiteBody(String title, String domain) {
    return '\"$title\" isn\'t saved for $domain. Fill anyway? Only do this if you\'re sure the site is genuine.';
  }

  @override
  String get autofillFill => 'Fill';

  @override
  String get autofillPickerTitle => 'Choose credentials';

  @override
  String autofillRequestedBy(String requester) {
    return 'Requested by: $requester';
  }

  @override
  String get autofillSearch => 'Search';

  @override
  String get autofillNoCredentials => 'No credentials found.';

  @override
  String get autofillSuggested => 'Suggested';

  @override
  String get autofillAllCredentials => 'All credentials';

  @override
  String get autofillOthers => 'Others';

  @override
  String get errorWrongCredentials => 'Wrong master password or Secret Key.';

  @override
  String get errorInvalidSecretKey =>
      'Invalid Secret Key: make sure you copied all of it.';

  @override
  String get errorLocked => 'The vault is locked.';

  @override
  String get errorNotInitialized => 'No vault found.';

  @override
  String get errorAlreadyInitialized => 'The vault already exists.';

  @override
  String get errorNotFound => 'Item not found.';

  @override
  String get errorInvalidLogin =>
      'Wrong master password or Secret Key, or no account with this Secret Key on the server.';

  @override
  String get errorAccountExists =>
      'This vault already has an account on the server: use \"I already have an account\" on your other devices.';

  @override
  String get errorInviteRequired =>
      'This server only accepts new accounts with an invite code: ask its administrator.';

  @override
  String get errorInvalidInvite =>
      'Invalid invite code: it may be mistyped, already used or expired.';

  @override
  String get errorRegistrationClosed =>
      'This server doesn\'t accept new accounts.';

  @override
  String get errorQuotaExceeded =>
      'Your account has reached the server\'s storage limit.';

  @override
  String get errorSessionExpired =>
      'The sync session has expired: reconnect this device.';

  @override
  String get errorTooManyRequests =>
      'Too many attempts. Try again in a few minutes.';

  @override
  String get errorInvalidServerUrl =>
      'Invalid server address: it must start with https://';

  @override
  String get errorNetwork =>
      'Server unreachable. Check your connection and the address.';

  @override
  String get errorNotLinked => 'This vault isn\'t linked to a server.';

  @override
  String errorInvalidInput(String details) {
    return 'Invalid value: $details';
  }

  @override
  String get errorPasswordRequired =>
      'For security, the master password is required (at least every 14 days and after a password change).';

  @override
  String errorInternal(String details) {
    return 'Internal error: $details';
  }

  @override
  String errorUnexpected(String details) {
    return 'Unexpected error: $details';
  }

  @override
  String get controllerDefaultDevice => 'Device';

  @override
  String get controllerMissingSecretKey => 'Secret Key missing';

  @override
  String get quickUnlockReason => 'Unlock the vault';

  @override
  String get quickUnlockFingerprint => 'fingerprint';

  @override
  String get quickUnlockCancelled => 'Verification cancelled';

  @override
  String clipboardCopied(String label, int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds seconds',
      one: '1 second',
    );
    return '$label copied. It will be cleared in $_temp0.';
  }
}
