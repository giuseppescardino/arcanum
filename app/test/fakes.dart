import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'package:arcanum/app/file_dialogs.dart';
import 'package:arcanum/app/groups.dart';
import 'package:arcanum/app/quick_unlock_store.dart';
import 'package:arcanum/app/secret_key_store.dart';
import 'package:arcanum/app/transfer.dart';
import 'package:arcanum/browser/bridge_clients.dart';
import 'package:arcanum/browser/bridge_crypto.dart';
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
      if (item.fields.kind == VaultItemKind.group) {
        if (to.isEmpty) _items.remove(item.id);
      } else {
        moved++;
      }
    }
    return moved;
  }

  @override
  Future<void> setGroupColor({required String path, int? color}) async {
    _requireUnlocked();
    path = normalizeGroup(path);
    _items.removeWhere(
      (_, i) => i.fields.kind == VaultItemKind.group && i.fields.group == path,
    );
    if (color == null || path.isEmpty) return;
    await addItem(
      fields: ItemFields(
        kind: VaultItemKind.group,
        title: '',
        username: '',
        password: '',
        urls: const [],
        notes: '',
        favorite: false,
        group: path,
        color: color,
      ),
    );
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
    color: f.color,
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

  /// Like iOS: the prompt fails unless the app is in the foreground.
  bool foregroundOnly = false;

  @override
  String get methodName => 'Test Biometrics';

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> save(String secret) async => stored = secret;

  @override
  Future<String?> read() async {
    final state = WidgetsBinding.instance.lifecycleState;
    if (foregroundOnly && state != AppLifecycleState.resumed) return null;
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
  String username = 'alice',
  String password = 'pw',
  bool favorite = false,
  String group = '',
  List<String> urls = const [],
}) => ItemFields(
  kind: VaultItemKind.login,
  title: title,
  username: username,
  password: password,
  urls: urls,
  notes: '',
  favorite: favorite,
  group: group,
  color: null,
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

/// Reversible stand-in for the bridge crypto: "ciphertext" is base64 of
/// `client|direction|plaintext`, so tests can read and forge messages.
class FakeBridgeCrypto implements BridgeCrypto {
  @override
  BridgePairing pairRespond(Uint8List extPub) {
    if (extPub.length != 32) {
      throw const VaultFailure(
        code: VaultFailureCode.invalidInput,
        message: '',
      );
    }
    return BridgePairing(
      appPub: Uint8List.fromList(List.filled(32, 9)),
      key: Uint8List.fromList(List.filled(32, extPub[1])),
      code: '123456',
    );
  }

  static String seal(String client, String dir, String plaintext) =>
      base64.encode(utf8.encode('$client|$dir|$plaintext'));

  static String open(String client, String dir, String ct) {
    final text = utf8.decode(base64.decode(ct));
    final prefix = '$client|$dir|';
    if (!text.startsWith(prefix)) {
      throw const VaultFailure(
        code: VaultFailureCode.invalidInput,
        message: '',
      );
    }
    return text.substring(prefix.length);
  }

  @override
  String openRequest(Uint8List key, String client, String ciphertext) {
    try {
      return open(client, 'req', ciphertext);
    } on FormatException {
      throw const VaultFailure(
        code: VaultFailureCode.invalidInput,
        message: '',
      );
    }
  }

  @override
  String sealResponse(Uint8List key, String client, String plaintext) =>
      seal(client, 'res', plaintext);
}

class MemoryBridgeClientStore implements BridgeClientStore {
  List<PairedBrowser> saved = [];

  @override
  Future<List<PairedBrowser>> load() async => List.of(saved);

  @override
  Future<void> save(List<PairedBrowser> browsers) async =>
      saved = List.of(browsers);
}
