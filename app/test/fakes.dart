import 'dart:convert';

import 'package:arcanum/app/quick_unlock_store.dart';
import 'package:arcanum/app/secret_key_store.dart';
import 'package:arcanum/src/rust/api/vault.dart';

const fakeSecretKey = 'PM1-AAAAAA-AAAAA-AAAAA-AAAAA-AAAAA';

/// In-memory stand-in for the Rust vault, so controller and widget tests
/// run without the native library.
class FakeVaultHandle implements VaultHandle {
  bool initialized = false;
  bool unlocked = false;
  String? _password;
  final Map<String, VaultItem> _items = {};
  int _nextId = 1;

  void _requireUnlocked() {
    if (!unlocked) {
      throw const VaultFailure(code: VaultFailureCode.locked, message: '');
    }
  }

  // ---- Quick unlock ----
  String? quickSecret;
  int _quickCounter = 0;

  /// Thrown by the next [quickUnlock] call, then cleared.
  VaultFailure? nextQuickFailure;

  @override
  Future<String> enableQuickUnlock() async {
    _requireUnlocked();
    return quickSecret = 'secret-${++_quickCounter}';
  }

  @override
  Future<void> quickUnlock({required String secret}) async {
    final failure = nextQuickFailure;
    nextQuickFailure = null;
    if (failure != null) throw failure;
    if (quickSecret == null) {
      throw const VaultFailure(
        code: VaultFailureCode.passwordRequired,
        message: '',
      );
    }
    if (secret != quickSecret) {
      throw const VaultFailure(
        code: VaultFailureCode.wrongCredentials,
        message: '',
      );
    }
    unlocked = true;
  }

  @override
  Future<void> disableQuickUnlock() async => quickSecret = null;

  @override
  Future<bool> hasQuickUnlock() async => quickSecret != null;

  // ---- Sync ----
  SyncInfo? link;
  int syncCalls = 0;
  int syncedRegistrations = 0;

  /// Thrown by the next [syncNow] call, then cleared.
  VaultFailure? nextSyncFailure;

  static const _summary = SyncSummary(pulled: 0, pushed: 0, conflicts: 0);

  @override
  Future<bool> isLinked() async => link != null;

  @override
  Future<SyncInfo?> syncInfo() async {
    _requireUnlocked();
    return link;
  }

  @override
  Future<SyncSummary> registerSync({
    required String serverUrl,
    required String email,
    required List<int> password,
    required String secretKey,
    required String deviceName,
  }) async {
    _requireUnlocked();
    if (utf8.decode(password) != _password) {
      throw const VaultFailure(
        code: VaultFailureCode.wrongCredentials,
        message: '',
      );
    }
    link = SyncInfo(serverUrl: serverUrl, email: email);
    syncedRegistrations++;
    return SyncSummary(pulled: 0, pushed: _items.length, conflicts: 0);
  }

  @override
  Future<SyncSummary> signIn({
    required String serverUrl,
    required String email,
    required List<int> password,
    required String secretKey,
    required String deviceName,
  }) async {
    if (secretKey != fakeSecretKey) {
      throw const VaultFailure(
        code: VaultFailureCode.invalidLogin,
        message: '',
      );
    }
    initialized = true;
    unlocked = true;
    _password = utf8.decode(password);
    link = SyncInfo(serverUrl: serverUrl, email: email);
    return _summary;
  }

  @override
  Future<SyncSummary> reconnectSync({
    required List<int> password,
    required String secretKey,
    required String deviceName,
  }) async {
    _requireUnlocked();
    _password = utf8.decode(password);
    return _summary;
  }

  @override
  Future<SyncSummary> syncNow() async {
    _requireUnlocked();
    syncCalls++;
    final failure = nextSyncFailure;
    nextSyncFailure = null;
    if (failure != null) throw failure;
    return _summary;
  }

  @override
  Future<void> unlinkSync() async => link = null;

  @override
  Future<void> signOut() async {
    link = null;
    initialized = false;
    unlocked = false;
    quickSecret = null;
    _password = null;
    _items.clear();
  }

  @override
  Future<bool> isInitialized() async => initialized;

  @override
  bool isUnlocked() => unlocked;

  @override
  Future<String> create({required List<int> password}) async {
    initialized = true;
    unlocked = true;
    _password = utf8.decode(password);
    return fakeSecretKey;
  }

  @override
  Future<void> unlock({
    required List<int> password,
    required String secretKey,
  }) async {
    if (utf8.decode(password) != _password || secretKey != fakeSecretKey) {
      throw const VaultFailure(
        code: VaultFailureCode.wrongCredentials,
        message: '',
      );
    }
    unlocked = true;
  }

  @override
  void lock() => unlocked = false;

  @override
  Future<void> changePassword({
    required List<int> current,
    required List<int> newPassword,
    required String secretKey,
  }) async {
    if (utf8.decode(current) != _password) {
      throw const VaultFailure(
        code: VaultFailureCode.wrongCredentials,
        message: '',
      );
    }
    _password = utf8.decode(newPassword);
  }

  @override
  Future<List<VaultItem>> listItems() async {
    _requireUnlocked();
    return _items.values.toList()..sort(
      (a, b) =>
          a.fields.title.toLowerCase().compareTo(b.fields.title.toLowerCase()),
    );
  }

  @override
  Future<VaultItem> addItem({required ItemFields fields}) async {
    _requireUnlocked();
    final item = VaultItem(id: '${_nextId++}', updatedAt: 0, fields: fields);
    return _items[item.id] = item;
  }

  @override
  Future<VaultItem> updateItem({
    required String id,
    required ItemFields fields,
  }) async {
    _requireUnlocked();
    if (!_items.containsKey(id)) {
      throw const VaultFailure(code: VaultFailureCode.notFound, message: '');
    }
    return _items[id] = VaultItem(id: id, updatedAt: 1, fields: fields);
  }

  @override
  Future<void> deleteItem({required String id}) async {
    _requireUnlocked();
    _items.remove(id);
  }

  @override
  Future<int> renameGroup({required String from, required String to}) async {
    _requireUnlocked();
    var moved = 0;
    for (final item in _items.values.toList()) {
      if (from.trim().isEmpty || item.fields.group != from.trim()) continue;
      _items[item.id] = VaultItem(
        id: item.id,
        updatedAt: 1,
        fields: _withGroup(item.fields, to.trim()),
      );
      moved++;
    }
    return moved;
  }

  static ItemFields _withGroup(ItemFields f, String group) => ItemFields(
    kind: f.kind,
    title: f.title,
    username: f.username,
    password: f.password,
    urls: f.urls,
    notes: f.notes,
    totp: f.totp,
    favorite: f.favorite,
    group: group,
  );

  // RustOpaqueInterface members are irrelevant for the fake.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeQuickUnlockStore implements QuickUnlockStore {
  FakeQuickUnlockStore({this.available = true});

  final bool available;
  String? stored;

  /// Simulates the user cancelling the biometric prompt.
  bool cancel = false;
  int prompts = 0;

  @override
  String get methodName => 'Test Biometrics';

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> save(String secret) async => stored = secret;

  @override
  Future<String?> read() async {
    prompts++;
    return cancel ? null : stored;
  }

  @override
  Future<void> delete() async => stored = null;
}

class MemorySecretKeyStore extends SecretKeyStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String secretKey) async => value = secretKey;

  @override
  Future<void> delete() async => value = null;
}

ItemFields login(
  String title, {
  String password = 'pw',
  bool favorite = false,
  String group = '',
}) => ItemFields(
  kind: VaultItemKind.login,
  title: title,
  username: 'alice',
  password: password,
  urls: const [],
  notes: '',
  favorite: favorite,
  group: group,
);
