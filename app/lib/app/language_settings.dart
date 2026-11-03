import 'dart:io';

import 'package:flutter/widgets.dart';

/// Persists the UI language choice. It lives outside the vault, so the
/// unlock screen and the autofill flow can use it before unlocking.
abstract class LanguageStore {
  Future<String?> read();
  Future<void> write(String? languageCode);
}

class FileLanguageStore implements LanguageStore {
  FileLanguageStore(this.path);

  final String path;

  @override
  Future<String?> read() async {
    try {
      final value = (await File(path).readAsString()).trim();
      return value.isEmpty ? null : value;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String? languageCode) async {
    final file = File(path);
    if (languageCode == null) {
      if (await file.exists()) await file.delete();
    } else {
      await file.writeAsString(languageCode);
    }
  }
}

class MemoryLanguageStore implements LanguageStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? languageCode) async => value = languageCode;
}

/// The language the user picked, or null to follow the system.
class LanguageSettings extends ChangeNotifier {
  LanguageSettings({LanguageStore? store})
    : store = store ?? MemoryLanguageStore();

  final LanguageStore store;

  /// Languages the UI is translated into, by code.
  static const supported = ['en', 'it'];

  Locale? locale;

  Future<void> load() async {
    final code = await store.read();
    locale = supported.contains(code) ? Locale(code!) : null;
    notifyListeners();
  }

  Future<void> select(Locale? value) async {
    locale = value;
    notifyListeners();
    await store.write(value?.languageCode);
  }
}

/// Makes [LanguageSettings] reachable from every route.
class LanguageScope extends InheritedNotifier<LanguageSettings> {
  const LanguageScope({
    super.key,
    required LanguageSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static LanguageSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageScope>()!.notifier!;
}
