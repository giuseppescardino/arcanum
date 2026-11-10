import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import 'groups.dart';
import 'messages.dart';
import 'quick_unlock_store.dart';
import 'secret_key_store.dart';

enum VaultStage { setup, emergencyKit, locked, unlocked }

String defaultDeviceName() {
  final os = switch (defaultTargetPlatform) {
    TargetPlatform.windows => 'Windows',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.android => 'Android',
    _ => l10n.controllerDefaultDevice,
  };
  try {
    return '$os · ${Platform.localHostname}';
  } catch (_) {
    return os;
  }
}

/// Single source of truth for the UI. All cryptography and networking
/// happen in Rust; this class only sequences calls and holds decrypted
/// items while unlocked.
class VaultController extends ChangeNotifier {
  VaultController({
    required this.handle,
    required this.secretKeys,
    this.autoLockAfter = const Duration(minutes: 5),
    this.syncDebounce = const Duration(seconds: 2),
    this.periodicSyncEvery = const Duration(minutes: 5),
    String Function()? deviceName,
    QuickUnlockStore? quickUnlock,
  }) : deviceName = deviceName ?? defaultDeviceName,
       quickUnlock = quickUnlock ?? PlatformQuickUnlockStore();

  final VaultHandle handle;
  final SecretKeyStore secretKeys;
  final Duration autoLockAfter;
  final Duration syncDebounce;
  final Duration periodicSyncEvery;
  final String Function() deviceName;
  final QuickUnlockStore quickUnlock;

  VaultStage stage = VaultStage.setup;
  bool hasStoredSecretKey = false;
  List<VaultItem> items = const [];

  /// Set only between account creation and Emergency Kit confirmation.
  String? pendingSecretKey;

  // ---- Quick (biometric) unlock ----
  bool quickUnlockAvailable = false;
  bool quickUnlockEnabled = false;

  // ---- Sync state ----
  bool linked = false;
  SyncInfo? syncInfo;
  bool syncing = false;
  String? syncError;
  bool sessionExpired = false;
  DateTime? lastSync;
  SyncSummary? lastSummary;

  Timer? _autoLockTimer;
  Timer? _syncDebounceTimer;
  Timer? _periodicSyncTimer;

  Future<void> init() async {
    final initialized = await handle.isInitialized();
    hasStoredSecretKey = await secretKeys.read() != null;
    linked = initialized && await handle.isLinked();
    quickUnlockAvailable = await quickUnlock.isAvailable();
    quickUnlockEnabled = initialized && await handle.hasQuickUnlock();
    stage = initialized ? VaultStage.locked : VaultStage.setup;
    notifyListeners();
  }

  Future<void> create(String password) async {
    final secretKey = await handle.create(password: utf8.encode(password));
    await secretKeys.write(secretKey);
    hasStoredSecretKey = true;
    pendingSecretKey = secretKey;
    items = const [];
    stage = VaultStage.emergencyKit;
    notifyListeners();
  }

  void confirmEmergencyKit() {
    pendingSecretKey = null;
    stage = VaultStage.unlocked;
    touch();
    notifyListeners();
  }

  /// Sets up this device from an existing server account.
  Future<void> signIn({
    required String serverUrl,
    required String password,
    required String secretKey,
  }) async {
    lastSummary = await handle.signIn(
      serverUrl: serverUrl,
      password: utf8.encode(password),
      secretKey: secretKey,
      deviceName: deviceName(),
    );
    await secretKeys.write(secretKey);
    hasStoredSecretKey = true;
    lastSync = DateTime.now();
    await _afterUnlock(syncFirst: false);
  }

  /// [secretKey] is required when none is stored on this device yet.
  Future<void> unlock(String password, {String? secretKey}) async {
    final key = secretKey ?? await secretKeys.read();
    if (key == null) {
      throw StateError(l10n.controllerMissingSecretKey);
    }
    await handle.unlock(password: utf8.encode(password), secretKey: key);
    if (secretKey != null) {
      await secretKeys.write(secretKey);
      hasStoredSecretKey = true;
    }
    await _afterUnlock(syncFirst: true);
  }

  /// Returns false when the user cancels the biometric prompt.
  Future<bool> unlockWithBiometrics() async {
    final secret = await quickUnlock.read();
    if (secret == null) return false;
    try {
      await handle.quickUnlock(secret: secret);
    } on VaultFailure catch (e) {
      if (e.code == VaultFailureCode.wrongCredentials) {
        // Stale secret (e.g. replaced on another enable): start over.
        await disableQuickUnlock();
      }
      rethrow;
    }
    await _afterUnlock(syncFirst: true);
    return true;
  }

  Future<void> enableQuickUnlock() async {
    final secret = await handle.enableQuickUnlock();
    try {
      await quickUnlock.save(secret);
    } catch (_) {
      await handle.disableQuickUnlock();
      rethrow;
    }
    quickUnlockEnabled = true;
    notifyListeners();
  }

  Future<void> disableQuickUnlock() async {
    await handle.disableQuickUnlock();
    await quickUnlock.delete();
    quickUnlockEnabled = false;
    notifyListeners();
  }

  /// Rust disables quick unlock whenever the password changes.
  Future<void> _refreshQuickUnlock() async {
    quickUnlockEnabled = await handle.hasQuickUnlock();
    if (!quickUnlockEnabled) await quickUnlock.delete();
    notifyListeners();
  }

  Future<void> _afterUnlock({required bool syncFirst}) async {
    await _reload();
    await _refreshSyncInfo();
    stage = VaultStage.unlocked;
    touch();
    notifyListeners();
    if (linked) {
      _startPeriodicSync();
      if (syncFirst) unawaited(syncNow());
    }
  }

  void lock() {
    if (stage != VaultStage.unlocked) return;
    _autoLockTimer?.cancel();
    _syncDebounceTimer?.cancel();
    _periodicSyncTimer?.cancel();
    handle.lock();
    items = const [];
    syncInfo = null;
    stage = VaultStage.locked;
    notifyListeners();
  }

  /// Removes the Secret Key from this device; the next unlock will need
  /// the Emergency Kit.
  Future<void> forgetSecretKey() async {
    await secretKeys.delete();
    hasStoredSecretKey = false;
    notifyListeners();
  }

  /// Signs this device out: revokes the server session, erases the local
  /// vault, the stored Secret Key and quick unlock, and returns to setup
  /// so a different account can be used.
  Future<void> signOut() async {
    _autoLockTimer?.cancel();
    _syncDebounceTimer?.cancel();
    _periodicSyncTimer?.cancel();
    await handle.signOut();
    await secretKeys.delete();
    await quickUnlock.delete();
    hasStoredSecretKey = false;
    quickUnlockEnabled = false;
    items = const [];
    linked = false;
    syncInfo = null;
    syncError = null;
    sessionExpired = false;
    lastSync = null;
    lastSummary = null;
    pendingSecretKey = null;
    stage = VaultStage.setup;
    notifyListeners();
  }

  /// When synced, the server is updated first and other devices are
  /// signed out until they reconnect with the new password.
  Future<void> changePassword(String current, String next) async {
    await handle.changePassword(
      current: utf8.encode(current),
      newPassword: utf8.encode(next),
      secretKey: await _secretKey(),
    );
    await _refreshQuickUnlock();
  }

  Future<void> save(ItemFields fields, {String? id}) async {
    if (id == null) {
      await handle.addItem(fields: fields);
    } else {
      await handle.updateItem(id: id, fields: fields);
    }
    await _reload();
    _scheduleSync();
  }

  Future<void> delete(String id) async {
    await handle.deleteItem(id: id);
    await _reload();
    _scheduleSync();
  }

  /// Paths of the groups in use, parents included, in tree order: each
  /// group is followed by its subgroups.
  List<String> get groups =>
      groupTree(items.map((i) => normalizeGroup(i.fields.group)));

  /// First-level groups only.
  List<String> get rootGroups => [
    for (final g in groups)
      if (groupDepth(g) == 0) g,
  ];

  /// Moves group [from], subgroups included, to [to]; an empty [to]
  /// ungroups their items.
  Future<void> renameGroup(String from, String to) async {
    final moved = await handle.renameGroup(from: from, to: to);
    if (moved == 0) return;
    await _reload();
    _scheduleSync();
  }

  // ---- Import ----

  /// [incoming] without the items the vault already holds and without
  /// repeats inside [incoming] itself.
  List<ItemFields> newItemsAmong(List<ItemFields> incoming) {
    final seen = {for (final i in items) _identity(i.fields)};
    return [
      for (final f in incoming)
        if (seen.add(_identity(f))) f,
    ];
  }

  static String _identity(ItemFields f) => [
    f.kind.name,
    f.title,
    f.username,
    f.password,
    f.urls.join(' '),
    if (f.kind == VaultItemKind.secureNote) f.notes,
  ].join('\u0000');

  /// Adds [fields] in one go; returns how many items were added.
  Future<int> importItems(List<ItemFields> fields) async {
    if (fields.isEmpty) return 0;
    final added = await handle.addItems(items: fields);
    await _reload();
    _scheduleSync();
    return added;
  }

  // ---- Lock on pause ----

  int _pauseLockHolds = 0;

  /// False while a system dialog (file picker) has the app in background
  /// on the user's behalf.
  bool get locksOnPause => _pauseLockHolds == 0;

  /// Runs [action] without locking when the app is paused: opening a
  /// system file dialog on mobile sends the app to the background.
  Future<T> keepUnlocked<T>(Future<T> Function() action) async {
    _pauseLockHolds++;
    try {
      return await action();
    } finally {
      _pauseLockHolds--;
    }
  }

  // ---- Sync ----

  /// Creates the server account for this vault and uploads it. [invite]
  /// is needed only by servers that accept invited registrations.
  Future<void> enableSync({
    required String serverUrl,
    required String password,
    String invite = '',
  }) async {
    lastSummary = await handle.registerSync(
      serverUrl: serverUrl,
      password: utf8.encode(password),
      secretKey: await _secretKey(),
      deviceName: deviceName(),
      invite: invite,
    );
    lastSync = DateTime.now();
    syncError = null;
    await _refreshSyncInfo();
    await _reload();
    _startPeriodicSync();
  }

  /// Signs this device in again; [password] is the account's current one.
  Future<void> reconnect(String password) async {
    lastSummary = await handle.reconnectSync(
      password: utf8.encode(password),
      secretKey: await _secretKey(),
      deviceName: deviceName(),
    );
    lastSync = DateTime.now();
    sessionExpired = false;
    syncError = null;
    await _reload();
    await _refreshQuickUnlock();
  }

  Future<void> disableSync() async {
    await handle.unlinkSync();
    _periodicSyncTimer?.cancel();
    _syncDebounceTimer?.cancel();
    sessionExpired = false;
    syncError = null;
    lastSync = null;
    lastSummary = null;
    await _refreshSyncInfo();
  }

  /// Pull + push. Never throws: failures end up in [syncError].
  Future<void> syncNow() async {
    if (!linked || syncing || stage != VaultStage.unlocked) return;
    syncing = true;
    notifyListeners();
    try {
      lastSummary = await handle.syncNow();
      lastSync = DateTime.now();
      syncError = null;
      sessionExpired = false;
      if (stage == VaultStage.unlocked) await _reload();
    } catch (e) {
      sessionExpired =
          e is VaultFailure && e.code == VaultFailureCode.sessionExpired;
      syncError = failureMessage(e);
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  void _scheduleSync() {
    if (!linked) return;
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(syncDebounce, syncNow);
  }

  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(periodicSyncEvery, (_) => syncNow());
  }

  Future<void> _refreshSyncInfo() async {
    linked = await handle.isLinked();
    syncInfo = linked ? await handle.syncInfo() : null;
    notifyListeners();
  }

  Future<String> _secretKey() async {
    final key = await secretKeys.read();
    if (key == null) {
      throw StateError(l10n.controllerMissingSecretKey);
    }
    return key;
  }

  /// Restarts the inactivity timer; called on every user interaction.
  void touch() {
    if (stage != VaultStage.unlocked) return;
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer(autoLockAfter, lock);
  }

  Future<void> _reload() async {
    items = await handle.listItems();
    notifyListeners();
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    _syncDebounceTimer?.cancel();
    _periodicSyncTimer?.cancel();
    handle.lock();
    super.dispose();
  }
}
