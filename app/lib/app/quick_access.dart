import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop stand-in for system autofill (Windows has no autofill API):
/// a global shortcut brings the vault forward with the search field
/// focused; Enter copies the first match's password and minimizes, so the
/// user can paste it into the app they came from.
class QuickAccess {
  QuickAccess._();

  static const shortcutLabel = 'Ctrl+Alt+P';

  /// Incremented whenever the search field should grab focus.
  static final searchRequests = ValueNotifier<int>(0);

  static bool _active = false;
  static bool get active => _active;

  static bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Never throws: quick access is a convenience, not a requirement.
  static Future<void> init() async {
    if (!_desktop) return;
    try {
      await windowManager.ensureInitialized();
      await hotKeyManager.unregisterAll();
      await hotKeyManager.register(
        HotKey(
          key: PhysicalKeyboardKey.keyP,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
        ),
        keyDownHandler: (_) => show(),
      );
      _active = true;
    } catch (e) {
      debugPrint('Quick access unavailable: $e');
    }
  }

  static Future<void> show() async {
    if (!_active) return;
    await windowManager.show();
    await windowManager.focus();
    searchRequests.value++;
  }

  /// Gets out of the way after copying, back to the previous app.
  static Future<void> hide() async {
    if (_active) await windowManager.minimize();
  }
}
