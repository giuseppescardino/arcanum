import 'dart:convert';
import 'dart:typed_data';

import 'package:arcanum/app/file_dialogs.dart';
import 'package:arcanum/app/groups.dart';
import 'package:arcanum/app/quick_unlock_store.dart';
import 'package:arcanum/app/secret_key_store.dart';
import 'package:arcanum/app/transfer.dart';
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
  String? lastInvite;

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
    required List<int> password,
    required String secretKey,
    required String deviceName,
    required String invite,
  }) async {
    _requireUnlocked();
    if (utf8.decode(password) != _password) {
      throw const VaultFailure(
        code: VaultFailureCode.wrongCredentials,
        message: '',
      );
    }
    lastInvite = invite;
    link = SyncInfo(serverUrl: serverUrl);
    syncedRegistrations++;
    return SyncSummary(pulled: 0, pushed: _items.length, conflicts: 0);
  }

  @override
  Future<SyncSummary> signIn({
    required String serverUrl,
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
    link = SyncInfo(serverUrl: serverUrl);
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
  Future<int> addItems({required List<ItemFields> items}) async {
    _requireUnlocked();
    for (final fields in items) {
      await addItem(fields: fields);
    }
    return items.length;
  }

  @override
  Future<int> renameGroup({required String from, required String to}) async {
    _requireUnlocked();
    from = normalizeGroup(from);
    to = normalizeGroup(to);
    if (from.isEmpty || from == to) return 0;
    var moved = 0;
    for (final item in _items.values.toList()) {
      final group = normalizeGroup(item.fields.group);
      if (!groupContains(from, group)) continue;
      final rest = group.substring(from.length);
      _items[item.id] = VaultItem(
        id: item.id,
        updatedAt: 1,
        fields: _withGroup(item.fields, to.isEmpty ? '' : '$to$rest'),
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
  List<String> urls = const [],
}) => ItemFields(
  kind: VaultItemKind.login,
  title: title,
  username: 'alice',
  password: password,
  urls: urls,
  notes: '',
  favorite: favorite,
  group: group,
);

/// Stand-in for the Rust formats: one `title|password|group` line per
/// item; a backup is the same text behind a `BACKUP:<password>` line.
class FakeTransfer implements Transfer {
  @override
  Future<String> exportCsv(List<ItemFields> items) async =>
      [for (final f in items) '${f.title}|${f.password}|${f.group}'].join('\n');

  @override
  Future<Uint8List> exportBackup(
    List<ItemFields> items,
    String password,
  ) async => utf8.encode('BACKUP:$password\n${await exportCsv(items)}');

  @override
  Future<ImportData> parse(Uint8List data, {String? password}) async {
    var lines = utf8.decode(data).split('\n');
    var format = ImportFormat.csv;
    if (lines.first.startsWith('BACKUP:')) {
      if (password == null) {
        throw const VaultFailure(
          code: VaultFailureCode.backupPasswordRequired,
          message: '',
        );
      }
      if (lines.first != 'BACKUP:$password') {
        throw const VaultFailure(
          code: VaultFailureCode.wrongCredentials,
          message: '',
        );
      }
      format = ImportFormat.arcanumBackup;
      lines = lines.sublist(1);
    }
    final rows = [
      for (final line in lines)
        if (line.isNotEmpty) line.split('|'),
    ];
    if (rows.any((r) => r.length != 3)) {
      throw const VaultFailure(
        code: VaultFailureCode.unsupportedFormat,
        message: '',
      );
    }
    return ImportData(
      format: format,
      items: [for (final r in rows) login(r[0], password: r[1], group: r[2])],
      skipped: 0,
    );
  }
}

/// Scripted open and save dialogs.
class FakeFileDialogs implements FileDialogs {
  /// What the next [pickFile] returns; null simulates a cancel.
  Uint8List? toPick;

  /// Makes the next [saveFile] report a cancel.
  bool cancelSave = false;

  String? savedName;
  Uint8List? savedBytes;

  @override
  bool get canSave => true;

  @override
  Future<Uint8List?> pickFile() async => toPick;

  @override
  Future<bool> saveFile({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (cancelSave) return false;
    savedName = name;
    savedBytes = bytes;
    return true;
  }
}
