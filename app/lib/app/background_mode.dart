import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

/// The app window, as far as running in the background needs it.
abstract class AppWindow {
  Future<void> show();
  Future<void> hide();

  /// When true, the close button calls the [onClose] callback instead of
  /// closing the window.
  Future<void> setPreventClose(bool value);

  /// Closes the window for good, which ends the app.
  Future<void> destroy();

  void onClose(void Function() callback);
}

enum TrayAction { open, lock, quit }

/// Localized texts of the tray icon and its menu.
@immutable
class TrayLabels {
  const TrayLabels({
    required this.tooltip,
    required this.open,
    required this.lock,
    required this.quit,
  });

  final String tooltip;
  final String open;
  final String lock;
  final String quit;

  @override
  bool operator ==(Object other) =>
      other is TrayLabels &&
      other.tooltip == tooltip &&
      other.open == open &&
      other.lock == lock &&
      other.quit == quit;

  @override
  int get hashCode => Object.hash(tooltip, open, lock, quit);
}

/// The icon in the system tray (menu bar on macOS).
abstract class SystemTray {
  /// Whether this desktop can show a tray icon at all.
  bool get supported;

  /// Shows the icon; false when it could not be created.
  bool create({
    required TrayLabels labels,
    required void Function(TrayAction) onAction,
  });

  void setLabels(TrayLabels labels);
  void dispose();
}

/// Starting the app when the user logs in.
abstract class LoginItem {
  bool get supported;

  /// Read from the system, so a change made in the OS settings shows up.
  bool get enabled;

  /// False when the system refused the change.
  bool setEnabled(bool value);
}

/// What is kept on disk. Launch at login is not: the system is the source
/// of truth for it.
@immutable
class BackgroundPrefs {
  const BackgroundPrefs({this.keepRunning = true});

  final bool keepRunning;
}

abstract class BackgroundPrefsStore {
  Future<BackgroundPrefs> read();
  Future<void> write(BackgroundPrefs prefs);
}

class FileBackgroundPrefsStore implements BackgroundPrefsStore {
  FileBackgroundPrefsStore(this.path);

  final String path;

  @override
  Future<BackgroundPrefs> read() async {
    try {
      final json = jsonDecode(await File(path).readAsString());
      if (json is! Map) return const BackgroundPrefs();
      return BackgroundPrefs(keepRunning: json['keepRunning'] != false);
    } on FileSystemException {
      return const BackgroundPrefs();
    } on FormatException {
      return const BackgroundPrefs();
    }
  }

  @override
  Future<void> write(BackgroundPrefs prefs) =>
      File(path).writeAsString(jsonEncode({'keepRunning': prefs.keepRunning}));
}

class MemoryBackgroundPrefsStore implements BackgroundPrefsStore {
  BackgroundPrefs value = const BackgroundPrefs();

  @override
  Future<BackgroundPrefs> read() async => value;

  @override
  Future<void> write(BackgroundPrefs prefs) async => value = prefs;
}

/// Desktop only: keeps the app, and the browser bridge with it, running
/// in the tray after the window is closed, and optionally starts it at
/// login. The vault still locks on its own timer whether or not the window
/// is visible.
///
/// The window is never hidden unless the tray icon is there to bring it
/// back: without a tray (e.g. GNOME without AppIndicator), closing the
/// window quits, as it always did.
class BackgroundMode extends ChangeNotifier {
  BackgroundMode({
    required this.window,
    required this.tray,
    required this.loginItem,
    required this.onLock,
    required this.onQuit,
    BackgroundPrefsStore? store,
  }) : store = store ?? MemoryBackgroundPrefsStore();

  final AppWindow window;
  final SystemTray tray;
  final LoginItem loginItem;
  final BackgroundPrefsStore store;

  /// Locks the vault (tray menu).
  final void Function() onLock;

  /// Stops what must not outlive the app (the browser bridge).
  final Future<void> Function() onQuit;

  bool keepRunning = true;
  bool trayAvailable = false;
  bool _quitting = false;

  bool get launchAtLoginSupported => loginItem.supported;
  bool get launchAtLogin => loginItem.supported && loginItem.enabled;

  /// Whether closing the window hides it instead of quitting.
  bool get hidesOnClose => trayAvailable && keepRunning;

  /// [startHidden] comes from the login item (`--hidden`); the native
  /// runner has then not shown the window. Never throws.
  Future<void> init({
    required TrayLabels labels,
    required bool startHidden,
  }) async {
    try {
      keepRunning = (await store.read()).keepRunning;
      trayAvailable =
          tray.supported && tray.create(labels: labels, onAction: _onAction);
      window.onClose(_onCloseRequested);
      await window.setPreventClose(hidesOnClose);
      if (startHidden && !hidesOnClose) await window.show();
    } catch (e) {
      debugPrint('Background mode unavailable: $e');
      if (startHidden) await window.show();
    }
    notifyListeners();
  }

  void setLabels(TrayLabels labels) {
    if (trayAvailable) tray.setLabels(labels);
  }

  Future<void> setKeepRunning(bool value) async {
    keepRunning = value;
    await window.setPreventClose(hidesOnClose);
    notifyListeners();
    await store.write(BackgroundPrefs(keepRunning: value));
  }

  /// False when the system refused the change.
  Future<bool> setLaunchAtLogin(bool value) async {
    if (!loginItem.supported) return false;
    final ok = loginItem.setEnabled(value);
    notifyListeners();
    return ok;
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await onQuit();
    } catch (e) {
      debugPrint('Cleanup before quitting failed: $e');
    }
    if (trayAvailable) tray.dispose();
    await window.destroy();
  }

  void _onCloseRequested() {
    if (hidesOnClose) {
      window.hide();
    } else {
      quit();
    }
  }

  void _onAction(TrayAction action) {
    switch (action) {
      case TrayAction.open:
        window.show();
      case TrayAction.lock:
        onLock();
      case TrayAction.quit:
        quit();
    }
  }
}

/// Makes the [BackgroundMode] reachable from the settings screen.
class BackgroundScope extends InheritedNotifier<BackgroundMode> {
  const BackgroundScope({
    super.key,
    required BackgroundMode mode,
    required super.child,
  }) : super(notifier: mode);

  /// Null on mobile and in tests that don't provide one.
  static BackgroundMode? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackgroundScope>()?.notifier;
}
