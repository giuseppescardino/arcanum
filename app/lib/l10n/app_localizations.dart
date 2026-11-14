import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('it'),
  ];

  /// Title of the language picker
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// Follow the device language
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @masterPassword.
  ///
  /// In en, this message translates to:
  /// **'Master password'**
  String get masterPassword;

  /// Product term, keep as is
  ///
  /// In en, this message translates to:
  /// **'Secret Key'**
  String get secretKey;

  /// No description provided for @reconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnect;

  /// Sync screen title and settings entry
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get syncTitle;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @noGroup.
  ///
  /// In en, this message translates to:
  /// **'No group'**
  String get noGroup;

  /// No description provided for @untitled.
  ///
  /// In en, this message translates to:
  /// **'(untitled)'**
  String get untitled;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @passwordsDontMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDontMatch;

  /// Reveal a hidden secret
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get show;

  /// No description provided for @hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// Clipboard label when copying an item's password
  ///
  /// In en, this message translates to:
  /// **'Password for \"{title}\"'**
  String vaultPasswordOf(String title);

  /// No description provided for @vaultDeleteGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete group \"{group}\"?'**
  String vaultDeleteGroupTitle(String group);

  /// No description provided for @vaultDeleteGroupBody.
  ///
  /// In en, this message translates to:
  /// **'Items are not deleted: those of the group and of its subgroups move to \"No group\".'**
  String get vaultDeleteGroupBody;

  /// No description provided for @vaultDeleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get vaultDeleteGroup;

  /// No description provided for @vaultForgetSecretKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove the Secret Key?'**
  String get vaultForgetSecretKeyTitle;

  /// No description provided for @vaultForgetSecretKeyBody.
  ///
  /// In en, this message translates to:
  /// **'Next time you unlock on this device you will need the Secret Key from your Emergency Kit. Make sure you have it.'**
  String get vaultForgetSecretKeyBody;

  /// No description provided for @vaultRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get vaultRemove;

  /// Main screen title
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get vaultTitle;

  /// No description provided for @vaultLock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get vaultLock;

  /// Switch label in settings; method is e.g. Face ID, Touch ID, fingerprint
  ///
  /// In en, this message translates to:
  /// **'Unlock with {method}'**
  String settingsQuickUnlock(String method);

  /// No description provided for @vaultEnableAutofill.
  ///
  /// In en, this message translates to:
  /// **'Enable autofill'**
  String get vaultEnableAutofill;

  /// No description provided for @vaultChangeMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Change master password'**
  String get vaultChangeMasterPassword;

  /// Settings entry that opens the About dialog
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get vaultAbout;

  /// Version line in the About dialog
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// One-line description of the app in the About dialog
  ///
  /// In en, this message translates to:
  /// **'Zero-knowledge password manager: your data is encrypted on this device before it is synced.'**
  String get aboutDescription;

  /// Settings entry and title of the breached-password check
  ///
  /// In en, this message translates to:
  /// **'Compromised passwords'**
  String get breachTitle;

  /// Privacy explanation on the breach check screen
  ///
  /// In en, this message translates to:
  /// **'Arcanum compares your passwords with the Have I Been Pwned archive of passwords exposed in data breaches. Only the first 5 characters of each password\'s SHA-1 hash leave this device, over an encrypted connection: neither the password nor its full hash is ever sent. Results stay in memory and are forgotten when the vault locks.'**
  String get breachExplanation;

  /// Switch that opts in to the automatic breach check
  ///
  /// In en, this message translates to:
  /// **'Automatic check and reminder'**
  String get breachAutoTitle;

  /// Subtitle of the automatic breach check switch
  ///
  /// In en, this message translates to:
  /// **'Check a password when you open or edit it, and remind me every month to check the whole vault'**
  String get breachAutoSubtitle;

  /// No vault-wide breach check done yet
  ///
  /// In en, this message translates to:
  /// **'The vault has never been fully checked'**
  String get breachNeverChecked;

  /// Date of the last complete vault-wide breach check
  ///
  /// In en, this message translates to:
  /// **'Last full check: {date}'**
  String breachLastCheck(String date);

  /// Button that checks every vault password against breaches
  ///
  /// In en, this message translates to:
  /// **'Check all passwords'**
  String get breachCheckAll;

  /// Progress of the vault-wide breach check
  ///
  /// In en, this message translates to:
  /// **'Checked {done} of {total}'**
  String breachProgress(int done, int total);

  /// Some passwords could not be checked (network error...)
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 password could not be checked} other{{count} passwords could not be checked}}: {error}'**
  String breachSomeFailed(int count, String error);

  /// Vault-wide check found nothing
  ///
  /// In en, this message translates to:
  /// **'None of your passwords appears in known breaches.'**
  String get breachNoneFound;

  /// Vault-wide check result
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 password appears in data breaches: change it} other{{count} passwords appear in data breaches: change them}}'**
  String breachCompromisedCount(int count);

  /// A password was found in breaches
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Found once in data breaches} other{Found {count} times in data breaches}}'**
  String breachFound(int count);

  /// A password was not found in breaches
  ///
  /// In en, this message translates to:
  /// **'Not found in known breaches'**
  String get breachNotFound;

  /// A breach check is running
  ///
  /// In en, this message translates to:
  /// **'Checking known breaches…'**
  String get breachChecking;

  /// A breach check failed: the password is not known to be safe
  ///
  /// In en, this message translates to:
  /// **'Could not check: {error}'**
  String breachCheckFailed(String error);

  /// Retry a failed breach check
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get breachRetry;

  /// One-off breach check of the password in the editor
  ///
  /// In en, this message translates to:
  /// **'Check if compromised'**
  String get breachCheckThis;

  /// Reminder banner before the first vault-wide check
  ///
  /// In en, this message translates to:
  /// **'Check whether any of your passwords appears in known data breaches.'**
  String get breachReminderFirst;

  /// Monthly reminder banner
  ///
  /// In en, this message translates to:
  /// **'Your passwords haven\'t been checked against known breaches for over a month.'**
  String get breachReminder;

  /// Dismiss the breach check reminder
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get breachLater;

  /// Start the vault-wide breach check from the reminder
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get breachCheckNow;

  /// Tooltip of the warning icon on a vault item
  ///
  /// In en, this message translates to:
  /// **'Password found in a data breach'**
  String get breachCompromisedTooltip;

  /// No description provided for @vaultForgetSecretKey.
  ///
  /// In en, this message translates to:
  /// **'Remove Secret Key from this device'**
  String get vaultForgetSecretKey;

  /// No description provided for @vaultSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out of this device'**
  String get vaultSignOut;

  /// No description provided for @vaultSignOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get vaultSignOutTitle;

  /// No description provided for @vaultSignOutBodySynced.
  ///
  /// In en, this message translates to:
  /// **'The vault will be erased from this device, together with its Secret Key. Your data stays on the sync server: to use it again, sign in with your master password and the Secret Key from your Emergency Kit.'**
  String get vaultSignOutBodySynced;

  /// No description provided for @vaultSignOutBodyLocal.
  ///
  /// In en, this message translates to:
  /// **'This vault is not synced to a server: signing out permanently erases all its items from this device. This cannot be undone.'**
  String get vaultSignOutBodyLocal;

  /// No description provided for @vaultSignOutSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Last sync failed, so recent changes may not be on the server and would be lost. Sign out anyway?'**
  String get vaultSignOutSyncFailed;

  /// No description provided for @vaultSignOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get vaultSignOutConfirm;

  /// No description provided for @vaultSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search · Enter copies the password'**
  String get vaultSearchHint;

  /// shortcut is the global hotkey label
  ///
  /// In en, this message translates to:
  /// **'Search · Enter copies the password · {shortcut} from anywhere'**
  String vaultSearchHintWithShortcut(String shortcut);

  /// No description provided for @vaultNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get vaultNew;

  /// No description provided for @vaultSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Sync is paused: this device needs to reconnect to the server.'**
  String get vaultSessionExpired;

  /// Filter chip showing items of every group
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get vaultAllGroups;

  /// No description provided for @vaultGroupActions.
  ///
  /// In en, this message translates to:
  /// **'Group actions'**
  String get vaultGroupActions;

  /// No description provided for @vaultRenameGroup.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get vaultRenameGroup;

  /// No description provided for @vaultGroupName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get vaultGroupName;

  /// No description provided for @vaultGroupMergeHint.
  ///
  /// In en, this message translates to:
  /// **'The group already exists: items will be merged.'**
  String get vaultGroupMergeHint;

  /// No description provided for @vaultRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get vaultRename;

  /// No description provided for @vaultCopyTotp.
  ///
  /// In en, this message translates to:
  /// **'Copy 2FA code'**
  String get vaultCopyTotp;

  /// No description provided for @vaultTotpCode.
  ///
  /// In en, this message translates to:
  /// **'2FA code'**
  String get vaultTotpCode;

  /// No description provided for @vaultCopyUsername.
  ///
  /// In en, this message translates to:
  /// **'Copy username'**
  String get vaultCopyUsername;

  /// No description provided for @vaultCopyPassword.
  ///
  /// In en, this message translates to:
  /// **'Copy password'**
  String get vaultCopyPassword;

  /// No description provided for @vaultNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results.'**
  String get vaultNoResults;

  /// No description provided for @vaultEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your vault is empty.\nAdd your first password with \"New\".'**
  String get vaultEmpty;

  /// No description provided for @vaultMasterPasswordChanged.
  ///
  /// In en, this message translates to:
  /// **'Master password updated.'**
  String get vaultMasterPasswordChanged;

  /// No description provided for @vaultCurrentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get vaultCurrentPassword;

  /// No description provided for @vaultRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get vaultRequired;

  /// No description provided for @vaultNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get vaultNewPassword;

  /// No description provided for @vaultMinLength.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{At least 1 character} other{At least {count} characters}}'**
  String vaultMinLength(int count);

  /// No description provided for @vaultRepeatNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Repeat new password'**
  String get vaultRepeatNewPassword;

  /// No description provided for @vaultChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get vaultChange;

  /// No description provided for @editorDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this item?'**
  String get editorDeleteTitle;

  /// No description provided for @editorDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone.'**
  String get editorDeleteBody;

  /// No description provided for @editorNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New item'**
  String get editorNewTitle;

  /// No description provided for @editorEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editorEditTitle;

  /// No description provided for @editorRemoveFavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get editorRemoveFavorite;

  /// No description provided for @editorFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get editorFavorite;

  /// No description provided for @editorSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get editorSave;

  /// Item type: website login
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get editorKindLogin;

  /// No description provided for @editorKindSecureNote.
  ///
  /// In en, this message translates to:
  /// **'Secure note'**
  String get editorKindSecureNote;

  /// No description provided for @editorTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get editorTitleLabel;

  /// No description provided for @editorTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Title is required'**
  String get editorTitleRequired;

  /// No description provided for @editorUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username / email'**
  String get editorUsernameLabel;

  /// No description provided for @editorGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get editorGenerate;

  /// No description provided for @editorWebsites.
  ///
  /// In en, this message translates to:
  /// **'Websites'**
  String get editorWebsites;

  /// No description provided for @editorWebsitesHelper.
  ///
  /// In en, this message translates to:
  /// **'One per line'**
  String get editorWebsitesHelper;

  /// No description provided for @editorTotpLabel.
  ///
  /// In en, this message translates to:
  /// **'2FA key (TOTP)'**
  String get editorTotpLabel;

  /// No description provided for @editorTotpHelper.
  ///
  /// In en, this message translates to:
  /// **'Secret key or otpauth:// URI from the site'**
  String get editorTotpHelper;

  /// No description provided for @editorTotpInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid 2FA key'**
  String get editorTotpInvalid;

  /// No description provided for @editorNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get editorNotes;

  /// No description provided for @editorGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get editorGroup;

  /// No description provided for @editorGroupHelper.
  ///
  /// In en, this message translates to:
  /// **'Pick an existing one or type a new one. Use / for subgroups, e.g. Work/Clients'**
  String get editorGroupHelper;

  /// No description provided for @totpCopyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get totpCopyCode;

  /// Clipboard label for a copied 2FA code
  ///
  /// In en, this message translates to:
  /// **'2FA code'**
  String get totpCode;

  /// No description provided for @strengthVeryWeak.
  ///
  /// In en, this message translates to:
  /// **'Very weak'**
  String get strengthVeryWeak;

  /// No description provided for @strengthWeak.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get strengthWeak;

  /// No description provided for @strengthFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get strengthFair;

  /// No description provided for @strengthStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get strengthStrong;

  /// No description provided for @strengthVeryStrong.
  ///
  /// In en, this message translates to:
  /// **'Very strong'**
  String get strengthVeryStrong;

  /// Strength level and estimated entropy in bits
  ///
  /// In en, this message translates to:
  /// **'{label} · {bits} bit'**
  String strengthLabelWithBits(String label, int bits);

  /// No description provided for @syncDisconnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect this device?'**
  String get syncDisconnectTitle;

  /// No description provided for @syncDisconnectBody.
  ///
  /// In en, this message translates to:
  /// **'The vault stays on this device but stops syncing. Data on the server and on your other devices is not touched.'**
  String get syncDisconnectBody;

  /// Confirm button of the disconnect dialog
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get syncDisconnect;

  /// No description provided for @syncActive.
  ///
  /// In en, this message translates to:
  /// **'Sync is on'**
  String get syncActive;

  /// No description provided for @syncServer.
  ///
  /// In en, this message translates to:
  /// **'Server: {url}'**
  String syncServer(String url);

  /// No description provided for @syncNotYetSynced.
  ///
  /// In en, this message translates to:
  /// **'Not synced yet in this session.'**
  String get syncNotYetSynced;

  /// time is HH:mm
  ///
  /// In en, this message translates to:
  /// **'Last synced: {time}'**
  String syncLastSync(String time);

  /// Counts of items received from and sent to the server
  ///
  /// In en, this message translates to:
  /// **'Last synced: {time} ({pulled} received, {pushed} sent)'**
  String syncLastSyncSummary(String time, int pulled, int pushed);

  /// Only used when conflicts > 0
  ///
  /// In en, this message translates to:
  /// **'Last synced: {time} ({pulled} received, {pushed} sent, {conflicts, plural, =1{1 conflict} other{{conflicts} conflicts}})'**
  String syncLastSyncSummaryConflicts(
    String time,
    int pulled,
    int pushed,
    int conflicts,
  );

  /// No description provided for @syncDisconnectDevice.
  ///
  /// In en, this message translates to:
  /// **'Disconnect this device'**
  String get syncDisconnectDevice;

  /// No description provided for @syncEncryptionNote.
  ///
  /// In en, this message translates to:
  /// **'Data is encrypted on this device before it is sent: the server only stores unreadable data and knows neither your master password nor your Secret Key.'**
  String get syncEncryptionNote;

  /// No description provided for @syncEnableTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync across your devices'**
  String get syncEnableTitle;

  /// Quotes the setupHaveAccount button; keep them consistent
  ///
  /// In en, this message translates to:
  /// **'Create an account on your sync server. Everything is encrypted here before it leaves: the server only sees unreadable data. On your other devices choose \"I already have an account\".'**
  String get syncEnableBody;

  /// No description provided for @syncConfirmMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Master password (to confirm)'**
  String get syncConfirmMasterPassword;

  /// No description provided for @syncEnable.
  ///
  /// In en, this message translates to:
  /// **'Turn on sync'**
  String get syncEnable;

  /// No description provided for @syncReconnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Reconnect this device'**
  String get syncReconnectTitle;

  /// No description provided for @syncReconnectBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the account\'s current master password. If you changed it on another device, use the new one: from now on it applies here too.'**
  String get syncReconnectBody;

  /// Screen title and submit button
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInTitle;

  /// No description provided for @signInIntro.
  ///
  /// In en, this message translates to:
  /// **'Connect this device to your account. You need the Secret Key from your Emergency Kit and your master password.'**
  String get signInIntro;

  /// No description provided for @unlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock the vault'**
  String get unlockTitle;

  /// No description provided for @unlockButton.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlockButton;

  /// method is the biometric method name, e.g. Face ID
  ///
  /// In en, this message translates to:
  /// **'Unlock with {method}'**
  String unlockWithMethod(String method);

  /// No description provided for @unlockEnterSecretKeyManually.
  ///
  /// In en, this message translates to:
  /// **'Enter the Secret Key manually'**
  String get unlockEnterSecretKeyManually;

  /// No description provided for @setupTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your vault'**
  String get setupTitle;

  /// No description provided for @setupIntro.
  ///
  /// In en, this message translates to:
  /// **'Your master password encrypts all your data on the device. Nobody, not even us, can recover it: make it long and memorable.'**
  String get setupIntro;

  /// Master password minimum length (always > 1)
  ///
  /// In en, this message translates to:
  /// **'At least {count} characters'**
  String setupMinLength(int count);

  /// No description provided for @setupRepeatMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Repeat master password'**
  String get setupRepeatMasterPassword;

  /// No description provided for @setupCreate.
  ///
  /// In en, this message translates to:
  /// **'Create vault'**
  String get setupCreate;

  /// No description provided for @setupHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'I already have an account: sign in'**
  String get setupHaveAccount;

  /// No description provided for @kitTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Secret Key'**
  String get kitTitle;

  /// No description provided for @kitIntro.
  ///
  /// In en, this message translates to:
  /// **'Together with your master password, the Secret Key is needed to open the vault on a new device or after reinstalling. It is saved in this device\'s keychain, but if you lose the device without having written it down, your data cannot be recovered.'**
  String get kitIntro;

  /// No description provided for @kitWriteItDown.
  ///
  /// In en, this message translates to:
  /// **'Write it on paper or store it somewhere safe, away from your master password.'**
  String get kitWriteItDown;

  /// No description provided for @kitSavedConfirm.
  ///
  /// In en, this message translates to:
  /// **'I have saved the Secret Key somewhere safe'**
  String get kitSavedConfirm;

  /// No description provided for @kitContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get kitContinue;

  /// Validator error when the master password is empty
  ///
  /// In en, this message translates to:
  /// **'Enter your master password'**
  String get commonEnterMasterPassword;

  /// No description provided for @commonInvalidSecretKey.
  ///
  /// In en, this message translates to:
  /// **'Invalid Secret Key'**
  String get commonInvalidSecretKey;

  /// No description provided for @commonSyncServer.
  ///
  /// In en, this message translates to:
  /// **'Sync server'**
  String get commonSyncServer;

  /// Example URL shown as hint
  ///
  /// In en, this message translates to:
  /// **'https://sync.example.com'**
  String get commonSyncServerHint;

  /// No description provided for @commonSyncServerInvalid.
  ///
  /// In en, this message translates to:
  /// **'Full address, e.g. https://sync.example.com'**
  String get commonSyncServerInvalid;

  /// No description provided for @commonInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get commonInviteCode;

  /// No description provided for @commonInviteCodeHelper.
  ///
  /// In en, this message translates to:
  /// **'Only if your server requires one'**
  String get commonInviteCodeHelper;

  /// No description provided for @generatorTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate password'**
  String get generatorTitle;

  /// No description provided for @generatorPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get generatorPassphrase;

  /// No description provided for @generatorRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get generatorRegenerate;

  /// No description provided for @generatorUse.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get generatorUse;

  /// No description provided for @generatorLength.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get generatorLength;

  /// No description provided for @generatorLowercase.
  ///
  /// In en, this message translates to:
  /// **'Lowercase (a-z)'**
  String get generatorLowercase;

  /// No description provided for @generatorUppercase.
  ///
  /// In en, this message translates to:
  /// **'Uppercase (A-Z)'**
  String get generatorUppercase;

  /// No description provided for @generatorDigits.
  ///
  /// In en, this message translates to:
  /// **'Numbers (0-9)'**
  String get generatorDigits;

  /// No description provided for @generatorSymbols.
  ///
  /// In en, this message translates to:
  /// **'Symbols (!@#…)'**
  String get generatorSymbols;

  /// No description provided for @generatorAvoidAmbiguous.
  ///
  /// In en, this message translates to:
  /// **'Avoid ambiguous characters (l, 1, O, 0…)'**
  String get generatorAvoidAmbiguous;

  /// No description provided for @generatorWords.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get generatorWords;

  /// No description provided for @generatorSeparator.
  ///
  /// In en, this message translates to:
  /// **'Separator'**
  String get generatorSeparator;

  /// Label of the space separator option.
  ///
  /// In en, this message translates to:
  /// **'space'**
  String get generatorSeparatorSpace;

  /// No description provided for @generatorCapitalize.
  ///
  /// In en, this message translates to:
  /// **'Capitalize words'**
  String get generatorCapitalize;

  /// No description provided for @generatorIncludeNumber.
  ///
  /// In en, this message translates to:
  /// **'Add a number'**
  String get generatorIncludeNumber;

  /// No description provided for @autofillNoVault.
  ///
  /// In en, this message translates to:
  /// **'There is no vault on this device yet. Open Arcanum to create one or sign in to your account.'**
  String get autofillNoVault;

  /// No description provided for @autofillClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get autofillClose;

  /// No description provided for @autofillDifferentSiteTitle.
  ///
  /// In en, this message translates to:
  /// **'Different site'**
  String get autofillDifferentSiteTitle;

  /// Confirmation before filling a credential on a site it isn't saved for.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" isn\'t saved for {domain}. Fill anyway? Only do this if you\'re sure the site is genuine.'**
  String autofillDifferentSiteBody(String title, String domain);

  /// No description provided for @autofillFill.
  ///
  /// In en, this message translates to:
  /// **'Fill'**
  String get autofillFill;

  /// No description provided for @autofillPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose credentials'**
  String get autofillPickerTitle;

  /// No description provided for @autofillRequestedBy.
  ///
  /// In en, this message translates to:
  /// **'Requested by: {requester}'**
  String autofillRequestedBy(String requester);

  /// No description provided for @autofillSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get autofillSearch;

  /// No description provided for @autofillNoCredentials.
  ///
  /// In en, this message translates to:
  /// **'No credentials found.'**
  String get autofillNoCredentials;

  /// No description provided for @autofillSuggested.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get autofillSuggested;

  /// No description provided for @autofillAllCredentials.
  ///
  /// In en, this message translates to:
  /// **'All credentials'**
  String get autofillAllCredentials;

  /// No description provided for @autofillOthers.
  ///
  /// In en, this message translates to:
  /// **'Others'**
  String get autofillOthers;

  /// No description provided for @errorWrongCredentials.
  ///
  /// In en, this message translates to:
  /// **'Wrong master password or Secret Key.'**
  String get errorWrongCredentials;

  /// No description provided for @errorInvalidSecretKey.
  ///
  /// In en, this message translates to:
  /// **'Invalid Secret Key: make sure you copied all of it.'**
  String get errorInvalidSecretKey;

  /// No description provided for @errorLocked.
  ///
  /// In en, this message translates to:
  /// **'The vault is locked.'**
  String get errorLocked;

  /// No description provided for @errorNotInitialized.
  ///
  /// In en, this message translates to:
  /// **'No vault found.'**
  String get errorNotInitialized;

  /// No description provided for @errorAlreadyInitialized.
  ///
  /// In en, this message translates to:
  /// **'The vault already exists.'**
  String get errorAlreadyInitialized;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Item not found.'**
  String get errorNotFound;

  /// No description provided for @errorInvalidLogin.
  ///
  /// In en, this message translates to:
  /// **'Wrong master password or Secret Key, or no account with this Secret Key on the server.'**
  String get errorInvalidLogin;

  /// No description provided for @errorAccountExists.
  ///
  /// In en, this message translates to:
  /// **'This vault already has an account on the server: use \"I already have an account\" on your other devices.'**
  String get errorAccountExists;

  /// No description provided for @errorInviteRequired.
  ///
  /// In en, this message translates to:
  /// **'This server only accepts new accounts with an invite code: ask its administrator.'**
  String get errorInviteRequired;

  /// No description provided for @errorInvalidInvite.
  ///
  /// In en, this message translates to:
  /// **'Invalid invite code: it may be mistyped, already used or expired.'**
  String get errorInvalidInvite;

  /// No description provided for @errorRegistrationClosed.
  ///
  /// In en, this message translates to:
  /// **'This server doesn\'t accept new accounts.'**
  String get errorRegistrationClosed;

  /// No description provided for @errorQuotaExceeded.
  ///
  /// In en, this message translates to:
  /// **'Your account has reached the server\'s storage limit.'**
  String get errorQuotaExceeded;

  /// No description provided for @errorSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'The sync session has expired: reconnect this device.'**
  String get errorSessionExpired;

  /// No description provided for @errorTooManyRequests.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in a few minutes.'**
  String get errorTooManyRequests;

  /// No description provided for @errorInvalidServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Invalid server address: it must start with https://'**
  String get errorInvalidServerUrl;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Server unreachable. Check your connection and the address.'**
  String get errorNetwork;

  /// No description provided for @errorNotLinked.
  ///
  /// In en, this message translates to:
  /// **'This vault isn\'t linked to a server.'**
  String get errorNotLinked;

  /// No description provided for @errorInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Invalid value: {details}'**
  String errorInvalidInput(String details);

  /// No description provided for @errorPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'For security, the master password is required (at least every 14 days and after a password change).'**
  String get errorPasswordRequired;

  /// No description provided for @errorInternal.
  ///
  /// In en, this message translates to:
  /// **'Internal error: {details}'**
  String errorInternal(String details);

  /// No description provided for @errorUnexpected.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error: {details}'**
  String errorUnexpected(String details);

  /// Fallback device name when the OS is unknown.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get controllerDefaultDevice;

  /// No description provided for @controllerMissingSecretKey.
  ///
  /// In en, this message translates to:
  /// **'Secret Key missing'**
  String get controllerMissingSecretKey;

  /// No description provided for @quickUnlockReason.
  ///
  /// In en, this message translates to:
  /// **'Unlock the vault'**
  String get quickUnlockReason;

  /// Biometric method name, used inside 'Unlock with {method}'.
  ///
  /// In en, this message translates to:
  /// **'fingerprint'**
  String get quickUnlockFingerprint;

  /// No description provided for @quickUnlockCancelled.
  ///
  /// In en, this message translates to:
  /// **'Verification cancelled'**
  String get quickUnlockCancelled;

  /// Snackbar after copying a secret; label is the copied field name.
  ///
  /// In en, this message translates to:
  /// **'{label} copied. It will be cleared in {seconds, plural, =1{1 second} other{{seconds} seconds}}.'**
  String clipboardCopied(String label, int seconds);

  /// No description provided for @vaultImport.
  ///
  /// In en, this message translates to:
  /// **'Import…'**
  String get vaultImport;

  /// No description provided for @vaultExport.
  ///
  /// In en, this message translates to:
  /// **'Export…'**
  String get vaultExport;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurity;

  /// No description provided for @settingsData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsData;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsDangerZone.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get settingsDangerZone;

  /// No description provided for @settingsSiteIcons.
  ///
  /// In en, this message translates to:
  /// **'Site icons'**
  String get settingsSiteIcons;

  /// No description provided for @vaultGroupPathHint.
  ///
  /// In en, this message translates to:
  /// **'Use / for subgroups, e.g. Work/Clients'**
  String get vaultGroupPathHint;

  /// No description provided for @exportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export items'**
  String get exportTitle;

  /// No description provided for @exportFormatBackup.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup'**
  String get exportFormatBackup;

  /// No description provided for @exportFormatCsv.
  ///
  /// In en, this message translates to:
  /// **'Plain CSV'**
  String get exportFormatCsv;

  /// No description provided for @exportBackupHint.
  ///
  /// In en, this message translates to:
  /// **'The file is encrypted with this password: you will need it to import the backup. It holds every item, notes included.'**
  String get exportBackupHint;

  /// No description provided for @exportCsvWarning.
  ///
  /// In en, this message translates to:
  /// **'The CSV file is not encrypted: anyone who opens it reads every password. Delete it as soon as you no longer need it.'**
  String get exportCsvWarning;

  /// No description provided for @exportPassword.
  ///
  /// In en, this message translates to:
  /// **'Backup password'**
  String get exportPassword;

  /// No description provided for @exportRepeatPassword.
  ///
  /// In en, this message translates to:
  /// **'Repeat the password'**
  String get exportRepeatPassword;

  /// No description provided for @exportAction.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportAction;

  /// No description provided for @exportEmpty.
  ///
  /// In en, this message translates to:
  /// **'There is nothing to export.'**
  String get exportEmpty;

  /// No description provided for @exportDone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item exported} other{{count} items exported}}'**
  String exportDone(int count);

  /// No description provided for @importTitle.
  ///
  /// In en, this message translates to:
  /// **'Import items'**
  String get importTitle;

  /// No description provided for @importFormat.
  ///
  /// In en, this message translates to:
  /// **'Recognized format: {format}'**
  String importFormat(String format);

  /// No description provided for @importFormatBackup.
  ///
  /// In en, this message translates to:
  /// **'Arcanum backup'**
  String get importFormatBackup;

  /// No description provided for @importNew.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item to import} other{{count} items to import}}'**
  String importNew(int count);

  /// No description provided for @importDuplicates.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 is already in the vault and will be skipped} other{{count} are already in the vault and will be skipped}}'**
  String importDuplicates(int count);

  /// No description provided for @importSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 cannot be imported (card, identity or empty row)} other{{count} cannot be imported (cards, identities or empty rows)}}'**
  String importSkipped(int count);

  /// No description provided for @importNothing.
  ///
  /// In en, this message translates to:
  /// **'There is nothing new to import.'**
  String get importNothing;

  /// No description provided for @importAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importAction;

  /// No description provided for @importOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get importOpen;

  /// No description provided for @importDone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item imported} other{{count} items imported}}'**
  String importDone(int count);

  /// No description provided for @importBackupPasswordBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the password you chose when you exported this backup.'**
  String get importBackupPasswordBody;

  /// No description provided for @importWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong backup password'**
  String get importWrongPassword;

  /// No description provided for @errorUnsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'The file is not in a format Arcanum can import.'**
  String get errorUnsupportedFormat;

  /// No description provided for @errorBackupPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'The backup password is required.'**
  String get errorBackupPasswordRequired;

  /// No description provided for @errorFile.
  ///
  /// In en, this message translates to:
  /// **'Could not read or write the file: {details}'**
  String errorFile(String details);

  /// No description provided for @vaultGroupColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get vaultGroupColor;

  /// No description provided for @vaultGroupColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Color of \"{group}\"'**
  String vaultGroupColorTitle(String group);

  /// No description provided for @vaultGroupColorNone.
  ///
  /// In en, this message translates to:
  /// **'No color'**
  String get vaultGroupColorNone;

  /// No description provided for @vaultGroupColorHint.
  ///
  /// In en, this message translates to:
  /// **'Subgroups without a color of their own use this one.'**
  String get vaultGroupColorHint;

  /// No description provided for @notesEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get notesEdit;

  /// No description provided for @notesPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get notesPreview;

  /// No description provided for @notesBold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get notesBold;

  /// No description provided for @notesItalic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get notesItalic;

  /// No description provided for @notesStrike.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get notesStrike;

  /// No description provided for @notesHeading.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get notesHeading;

  /// No description provided for @notesBulletList.
  ///
  /// In en, this message translates to:
  /// **'Bulleted list'**
  String get notesBulletList;

  /// No description provided for @notesNumberedList.
  ///
  /// In en, this message translates to:
  /// **'Numbered list'**
  String get notesNumberedList;

  /// No description provided for @notesChecklist.
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get notesChecklist;

  /// No description provided for @notesQuote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get notesQuote;

  /// No description provided for @notesCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get notesCode;

  /// No description provided for @notesLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get notesLink;

  /// No description provided for @notesDivider.
  ///
  /// In en, this message translates to:
  /// **'Divider'**
  String get notesDivider;

  /// No description provided for @notesEmptyPreview.
  ///
  /// In en, this message translates to:
  /// **'Nothing to show.'**
  String get notesEmptyPreview;

  /// No description provided for @notesOpenLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Open link?'**
  String get notesOpenLinkTitle;

  /// No description provided for @notesOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get notesOpen;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @editorKindWifi.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get editorKindWifi;

  /// No description provided for @editorKindCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get editorKindCard;

  /// No description provided for @wifiSsid.
  ///
  /// In en, this message translates to:
  /// **'Network name (SSID)'**
  String get wifiSsid;

  /// No description provided for @wifiSsidRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the network name.'**
  String get wifiSsidRequired;

  /// No description provided for @wifiSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get wifiSecurity;

  /// No description provided for @wifiSecurityWpa.
  ///
  /// In en, this message translates to:
  /// **'WPA/WPA2/WPA3'**
  String get wifiSecurityWpa;

  /// No description provided for @wifiSecurityWep.
  ///
  /// In en, this message translates to:
  /// **'WEP'**
  String get wifiSecurityWep;

  /// No description provided for @wifiSecurityNone.
  ///
  /// In en, this message translates to:
  /// **'None (open network)'**
  String get wifiSecurityNone;

  /// No description provided for @wifiHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden network'**
  String get wifiHidden;

  /// No description provided for @wifiShowQr.
  ///
  /// In en, this message translates to:
  /// **'Show QR code'**
  String get wifiShowQr;

  /// No description provided for @wifiQrHint.
  ///
  /// In en, this message translates to:
  /// **'Scan it with the other phone\'s camera to join the network.'**
  String get wifiQrHint;

  /// No description provided for @wifiQrSemantics.
  ///
  /// In en, this message translates to:
  /// **'QR code to join {ssid}'**
  String wifiQrSemantics(String ssid);

  /// No description provided for @cardHolder.
  ///
  /// In en, this message translates to:
  /// **'Cardholder'**
  String get cardHolder;

  /// No description provided for @cardNumber.
  ///
  /// In en, this message translates to:
  /// **'Card number'**
  String get cardNumber;

  /// No description provided for @cardNumberValid.
  ///
  /// In en, this message translates to:
  /// **'{brand} · valid number'**
  String cardNumberValid(String brand);

  /// No description provided for @cardNumberTooShort.
  ///
  /// In en, this message translates to:
  /// **'The number is too short.'**
  String get cardNumberTooShort;

  /// No description provided for @cardNumberWrongLength.
  ///
  /// In en, this message translates to:
  /// **'Wrong number of digits for {brand}.'**
  String cardNumberWrongLength(String brand);

  /// No description provided for @cardBrandUnknown.
  ///
  /// In en, this message translates to:
  /// **'this card'**
  String get cardBrandUnknown;

  /// No description provided for @cardNumberChecksum.
  ///
  /// In en, this message translates to:
  /// **'Invalid number: check the digits.'**
  String get cardNumberChecksum;

  /// No description provided for @cardExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expiry'**
  String get cardExpiry;

  /// No description provided for @cardExpiryHint.
  ///
  /// In en, this message translates to:
  /// **'MM/YY'**
  String get cardExpiryHint;

  /// No description provided for @cardExpiryInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use the MM/YY format.'**
  String get cardExpiryInvalid;

  /// No description provided for @cardExpired.
  ///
  /// In en, this message translates to:
  /// **'Card expired'**
  String get cardExpired;

  /// No description provided for @cardCvv.
  ///
  /// In en, this message translates to:
  /// **'CVV'**
  String get cardCvv;

  /// No description provided for @cardPin.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get cardPin;

  /// No description provided for @vaultCopyCardNumber.
  ///
  /// In en, this message translates to:
  /// **'Copy card number'**
  String get vaultCopyCardNumber;

  /// No description provided for @vaultShowWifiQr.
  ///
  /// In en, this message translates to:
  /// **'Show Wi-Fi QR code'**
  String get vaultShowWifiQr;

  /// No description provided for @vaultExpiresOn.
  ///
  /// In en, this message translates to:
  /// **'exp. {expiry}'**
  String vaultExpiresOn(String expiry);

  /// No description provided for @browsersTitle.
  ///
  /// In en, this message translates to:
  /// **'Connected browsers'**
  String get browsersTitle;

  /// No description provided for @browsersIntro.
  ///
  /// In en, this message translates to:
  /// **'Connect the Arcanum extension for Chrome, Opera or Safari: it fills and saves passwords while the app is unlocked.'**
  String get browsersIntro;

  /// No description provided for @browsersConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect browser'**
  String get browsersConnect;

  /// No description provided for @browsersWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the browser… Open the Arcanum extension and press Connect within 2 minutes.'**
  String get browsersWaiting;

  /// No description provided for @browsersNone.
  ///
  /// In en, this message translates to:
  /// **'No connected browsers'**
  String get browsersNone;

  /// No description provided for @browsersRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get browsersRevoke;

  /// When a browser was paired
  ///
  /// In en, this message translates to:
  /// **'Connected on {date}'**
  String browsersConnectedOn(String date);

  /// Pairing confirmation title
  ///
  /// In en, this message translates to:
  /// **'Connect {name}?'**
  String browsersPairTitle(String name);

  /// No description provided for @browsersPairBody.
  ///
  /// In en, this message translates to:
  /// **'Type the 6-digit code shown by the browser\'s Arcanum extension. If the browser shows no code, reject.'**
  String get browsersPairBody;

  /// No description provided for @browsersReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get browsersReject;

  /// No description provided for @browsersApprove.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get browsersApprove;

  /// No description provided for @browsersPortsBusy.
  ///
  /// In en, this message translates to:
  /// **'The browser connection could not start: ports 47613–47615 are in use.'**
  String get browsersPortsBusy;

  /// No description provided for @browsersWrongCode.
  ///
  /// In en, this message translates to:
  /// **'Wrong code'**
  String get browsersWrongCode;

  /// No description provided for @itemEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get itemEdit;

  /// No description provided for @itemUpdatedOn.
  ///
  /// In en, this message translates to:
  /// **'Edited {date}'**
  String itemUpdatedOn(String date);

  /// No description provided for @itemExpiresOn.
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String itemExpiresOn(String date);

  /// No description provided for @itemExpiredOn.
  ///
  /// In en, this message translates to:
  /// **'Expired {date}'**
  String itemExpiredOn(String date);

  /// No description provided for @expiryExpiredTooltip.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expiryExpiredTooltip;

  /// No description provided for @expirySoonTooltip.
  ///
  /// In en, this message translates to:
  /// **'Expiring soon'**
  String get expirySoonTooltip;

  /// No description provided for @editorExpiryLabel.
  ///
  /// In en, this message translates to:
  /// **'Expiry date'**
  String get editorExpiryLabel;

  /// No description provided for @editorExpiryHelper.
  ///
  /// In en, this message translates to:
  /// **'Optional. The item is flagged as the date approaches.'**
  String get editorExpiryHelper;

  /// No description provided for @editorExpiryClear.
  ///
  /// In en, this message translates to:
  /// **'Clear expiry date'**
  String get editorExpiryClear;

  /// No description provided for @vaultFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get vaultFavorites;

  /// No description provided for @vaultExpiring.
  ///
  /// In en, this message translates to:
  /// **'Expiring'**
  String get vaultExpiring;

  /// No description provided for @vaultGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get vaultGroups;

  /// No description provided for @vaultSelectItem.
  ///
  /// In en, this message translates to:
  /// **'Select an item to see its details.'**
  String get vaultSelectItem;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
