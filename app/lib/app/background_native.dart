import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nativeapi/nativeapi.dart' as native show LaunchAtLogin;
import 'package:tray_manager/tray_manager.dart' as tm;
import 'package:window_manager/window_manager.dart';

import 'background_mode.dart';

/// [AppWindow] on top of window_manager.
class DesktopAppWindow with WindowListener implements AppWindow {
  DesktopAppWindow() {
    windowManager.addListener(this);
  }

  void Function()? _onClose;

  @override
  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hide() => windowManager.hide();

  @override
  Future<void> setPreventClose(bool value) =>
      windowManager.setPreventClose(value);

  @override
  Future<void> destroy() => windowManager.destroy();

  @override
  void onClose(void Function() callback) => _onClose = callback;

  @override
  void onWindowClose() => _onClose?.call();
}

/// [SystemTray] on top of tray_manager's native API.
class DesktopSystemTray implements SystemTray {
  tm.TrayIcon? _icon;
  tm.MenuItem? _open;
  tm.MenuItem? _lock;
  tm.MenuItem? _quit;

  @override
  bool get supported {
    try {
      return tm.TrayManager.instance.isSupported();
    } catch (e) {
      debugPrint('Tray unavailable: $e');
      return false;
    }
  }

  @override
  bool create({
    required TrayLabels labels,
    required void Function(TrayAction) onAction,
  }) {
    final icon = tm.TrayIcon.create();
    if (icon == null) return false;
    // macOS wants a monochrome template image that follows the menu bar.
    final image = Platform.isMacOS
        ? tm.ImageAsset.fromAsset('assets/tray/tray_icon_template.png')
        : tm.ImageAsset.fromAsset('assets/tray/tray_icon.png');
    if (image == null) {
      icon.dispose();
      return false;
    }
    icon.icon = image;
    if (Platform.isMacOS) icon.isIconTemplate = true;

    tm.MenuItem item(String label, TrayAction action) {
      final entry = tm.MenuItem.createWithLabelAndType(
        label,
        tm.MenuItemType.normal,
      )!;
      entry.addListener((event) {
        if (event is tm.MenuItemClickedEvent) onAction(action);
      });
      return entry;
    }

    final menu = tm.Menu.create()!;
    menu.addItem(_open = item(labels.open, TrayAction.open));
    menu.addItem(_lock = item(labels.lock, TrayAction.lock));
    menu.addSeparator();
    menu.addItem(_quit = item(labels.quit, TrayAction.quit));
    icon.setContextMenu(menu);
    icon.setTooltip(labels.tooltip);

    // macOS: a click on a menu bar item opens its menu. Windows: left click
    // opens the window, right click the menu. Linux panels open the menu
    // themselves and report no clicks.
    if (Platform.isMacOS) {
      icon.setContextMenuTrigger(tm.ContextMenuTrigger.clicked);
    } else {
      icon.setContextMenuTrigger(tm.ContextMenuTrigger.rightClicked);
      icon.addListener((event) {
        if (event is tm.TrayIconClickedEvent ||
            event is tm.TrayIconDoubleClickedEvent) {
          onAction(TrayAction.open);
        }
      });
    }
    if (!icon.setVisible(true)) {
      icon.dispose();
      return false;
    }
    // Kept for as long as the icon must stay: a collected wrapper removes it.
    _icon = icon;
    return true;
  }

  @override
  void setLabels(TrayLabels labels) {
    _icon?.setTooltip(labels.tooltip);
    _open?.label = labels.open;
    _lock?.label = labels.lock;
    _quit?.label = labels.quit;
  }

  @override
  void dispose() {
    _icon?.dispose();
    _icon = null;
  }
}

/// [LoginItem] on top of nativeapi: the Run key on Windows, an XDG
/// autostart entry on Linux, SMAppService on macOS 13+.
///
/// macOS starts the app without arguments, so there it opens with its
/// window shown; elsewhere `--hidden` keeps it in the tray.
class DesktopLoginItem implements LoginItem {
  DesktopLoginItem._(this._item);

  static const _id = 'io.github.giuseppescardino.arcanum';

  /// Null when the platform has no login items.
  static DesktopLoginItem? create() {
    try {
      if (!native.LaunchAtLogin.isSupported()) return null;
      final item = Platform.isMacOS
          ? native.LaunchAtLogin.create()
          : native.LaunchAtLogin.createWithIdAndDisplayName(_id, 'Arcanum');
      if (item == null) return null;
      if (!Platform.isMacOS) {
        item.setProgram(Platform.resolvedExecutable, const ['--hidden']);
      }
      return DesktopLoginItem._(item);
    } catch (e) {
      debugPrint('Launch at login unavailable: $e');
      return null;
    }
  }

  final native.LaunchAtLogin _item;

  @override
  bool get supported => true;

  @override
  bool get enabled {
    try {
      return _item.isEnabled;
    } catch (_) {
      return false;
    }
  }

  @override
  bool setEnabled(bool value) {
    try {
      return value ? _item.enable() : _item.disable();
    } catch (e) {
      debugPrint('Cannot change launch at login: $e');
      return false;
    }
  }
}

/// Stand-in where the platform has no login items.
class NoLoginItem implements LoginItem {
  const NoLoginItem();

  @override
  bool get supported => false;

  @override
  bool get enabled => false;

  @override
  bool setEnabled(bool value) => false;
}
