import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../src/rust/api/tools.dart' as rust;

/// Asks Have I Been Pwned how often a password appears in known breaches.
/// Implemented in Rust (only a 5-digit SHA-1 prefix leaves the device);
/// swappable so tests run without the network or the native library.
abstract class BreachApi {
  Future<int> pwnedCount(String password);
}

class RustBreachApi implements BreachApi {
  const RustBreachApi();

  @override
  Future<int> pwnedCount(String password) =>
      rust.pwnedPasswordCount(password: password);
}

BreachApi breachApi = const RustBreachApi();

/// What is kept on disk: the opt-in and when the vault was last checked.
/// No password, hash or result is ever stored.
class BreachPrefs {
  const BreachPrefs({this.enabled = false, this.lastCheck});

  final bool enabled;
  final DateTime? lastCheck;
}

abstract class BreachPrefsStore {
  Future<BreachPrefs> read();
  Future<void> write(BreachPrefs prefs);
}

class FileBreachPrefsStore implements BreachPrefsStore {
  FileBreachPrefsStore(this.path);

  final String path;

  @override
  Future<BreachPrefs> read() async {
    try {
      final json = jsonDecode(await File(path).readAsString());
      if (json is! Map) return const BreachPrefs();
      final last = json['lastCheck'];
      return BreachPrefs(
        enabled: json['enabled'] == true,
        lastCheck: last is int
            ? DateTime.fromMillisecondsSinceEpoch(last)
            : null,
      );
    } on FileSystemException {
      return const BreachPrefs();
    } on FormatException {
      return const BreachPrefs();
    }
  }

  @override
  Future<void> write(BreachPrefs prefs) => File(path).writeAsString(
    jsonEncode({
      'enabled': prefs.enabled,
      'lastCheck': prefs.lastCheck?.millisecondsSinceEpoch,
    }),
  );
}

class MemoryBreachPrefsStore implements BreachPrefsStore {
  BreachPrefs value = const BreachPrefs();

  @override
  Future<BreachPrefs> read() async => value;

  @override
  Future<void> write(BreachPrefs prefs) async => value = prefs;
}

/// Breached-password check: single passwords (item editor) and the whole
/// vault (one button). Results live in memory only and are dropped when
/// the vault locks.
class BreachChecker extends ChangeNotifier {
  BreachChecker({BreachPrefsStore? store, DateTime Function()? clock})
    : store = store ?? MemoryBreachPrefsStore(),
      _clock = clock ?? DateTime.now;

  final BreachPrefsStore store;
  final DateTime Function() _clock;

  /// How often the vault should be checked again.
  static const checkInterval = Duration(days: 30);

  /// Parallel requests during a vault-wide check.
  static const _parallel = 4;

  /// Automatic check of the password open in the editor, plus a reminder
  /// when the vault is due for a check. Off until the user opts in.
  bool enabled = false;
  DateTime? lastCheck;

  final _counts = <String, int>{};
  final _errors = <String, Object>{};
  final _pending = <String, Future<void>>{};

  /// Bumped by [clear] so a check still running after a lock is dropped.
  int _generation = 0;

  bool running = false;
  int done = 0;
  int total = 0;

  /// Passwords the last vault-wide check could not verify, and one cause.
  int failed = 0;
  Object? lastError;

  /// Whether a vault-wide check finished since the vault was unlocked.
  bool hasResults = false;

  bool _reminderDismissed = false;

  Future<void> load() async {
    final prefs = await store.read();
    enabled = prefs.enabled;
    lastCheck = prefs.lastCheck;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    notifyListeners();
    await _save();
  }

  /// Times [password] was found in breaches; null if not checked yet.
  int? countFor(String password) => _counts[password];

  /// Why the last check of [password] failed, if it did.
  Object? errorFor(String password) => _errors[password];

  bool isChecking(String password) => _pending.containsKey(password);

  bool get checkDue =>
      enabled &&
      !_reminderDismissed &&
      !running &&
      (lastCheck == null || _clock().difference(lastCheck!) >= checkInterval);

  void dismissReminder() {
    _reminderDismissed = true;
    notifyListeners();
  }

  /// Checks one password, unless it is already known or being checked.
  Future<void> check(String password, {bool force = false}) {
    if (password.isEmpty) return Future.value();
    if (!force && _counts.containsKey(password)) return Future.value();
    final pending = _pending[password];
    if (pending != null) return pending;
    final future = _pending[password] = _check(password, _generation);
    notifyListeners();
    return future;
  }

  Future<void> _check(String password, int generation) async {
    try {
      final count = await breachApi.pwnedCount(password);
      if (generation != _generation) return;
      _counts[password] = count;
      _errors.remove(password);
    } catch (e) {
      if (generation != _generation) return;
      _errors[password] = e;
    } finally {
      if (generation == _generation) {
        _pending.remove(password);
        notifyListeners();
      }
    }
  }

  /// Checks every distinct, non-empty password again.
  Future<void> checkAll(Iterable<String> passwords) async {
    if (running) return;
    final distinct = passwords.where((p) => p.isNotEmpty).toSet().toList();
    final generation = _generation;
    running = true;
    done = 0;
    total = distinct.length;
    failed = 0;
    lastError = null;
    notifyListeners();

    var next = 0;
    Future<void> worker() async {
      while (next < distinct.length && generation == _generation) {
        final password = distinct[next++];
        await check(password, force: true);
        if (generation != _generation) return;
        final error = _errors[password];
        if (error != null) {
          failed++;
          lastError = error;
        }
        done++;
        notifyListeners();
      }
    }

    await Future.wait([for (var i = 0; i < _parallel; i++) worker()]);
    if (generation != _generation) return;
    running = false;
    hasResults = true;
    if (failed == 0) {
      lastCheck = _clock();
      _reminderDismissed = false;
      await _save();
    }
    notifyListeners();
  }

  /// Forgets every result (called when the vault locks).
  void clear() {
    _generation++;
    _counts.clear();
    _errors.clear();
    _pending.clear();
    running = false;
    done = total = failed = 0;
    lastError = null;
    hasResults = false;
    _reminderDismissed = false;
    notifyListeners();
  }

  Future<void> _save() =>
      store.write(BreachPrefs(enabled: enabled, lastCheck: lastCheck));
}

/// Makes the [BreachChecker] reachable from every route.
class BreachScope extends InheritedNotifier<BreachChecker> {
  const BreachScope({
    super.key,
    required BreachChecker checker,
    required super.child,
  }) : super(notifier: checker);

  /// Null outside the main app (e.g. the autofill flow).
  static BreachChecker? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BreachScope>()?.notifier;
}
