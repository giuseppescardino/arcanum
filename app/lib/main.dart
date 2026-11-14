import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'app/android_language.dart';
import 'app/background_mode.dart';
import 'app/background_native.dart';
import 'app/breach_check.dart';
import 'app/favicons.dart';
import 'app/language_settings.dart';
import 'app/quick_access.dart';
import 'app/secret_key_store.dart';
import 'app/tools.dart';
import 'app/vault_controller.dart';
import 'autofill/autofill_app.dart';
import 'browser/bridge_clients.dart';
import 'browser/bridge_crypto.dart';
import 'browser/bridge_handler.dart';
import 'browser/bridge_server.dart';
import 'autofill/autofill_bridge.dart';
import 'l10n/app_localizations.dart';
import 'src/rust/api/vault.dart';
import 'src/rust/frb_generated.dart';
import 'ui/app.dart';

Future<LanguageSettings> _loadLanguage() async {
  final dir = await getApplicationSupportDirectory();
  final settings = LanguageSettings(
    store: FileLanguageStore('${dir.path}/language'),
  );
  await settings.load();
  return settings;
}

Future<BreachChecker> _loadBreachChecker() async {
  final dir = await getApplicationSupportDirectory();
  final checker = BreachChecker(
    store: FileBreachPrefsStore('${dir.path}/breach_check.json'),
  );
  await checker.load();
  return checker;
}

Future<FaviconCache> _loadFavicons() async {
  final dir = await getApplicationSupportDirectory();
  final cache = FaviconCache(prefsPath: '${dir.path}/site_icons_off');
  await cache.load();
  return cache;
}

Future<VaultController> _openVault() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final dir = await getApplicationSupportDirectory();
  final handle = await VaultHandle.open(path: '${dir.path}/vault.db');
  final controller = VaultController(
    handle: handle,
    secretKeys: SecretKeyStore(),
  );
  await controller.init();
  return controller;
}

bool get _isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// Brings the window forward: browser extension, tray and quick access.
Future<void> _showWindow() async {
  try {
    await windowManager.show();
    await windowManager.focus();
  } catch (e) {
    debugPrint('Cannot bring the window forward: $e');
  }
}

/// Loopback server for the browser extension, desktop only. Never throws:
/// the browser connection is a convenience, not a requirement.
Future<BridgeServer?> _startBrowserBridge(VaultController controller) async {
  if (!_isDesktop) return null;
  final server = BridgeServer(
    handler: BridgeHandler(
      controller: controller,
      tools: const RustTools(),
      showApp: _showWindow,
    ),
    crypto: const RustBridgeCrypto(),
    store: SecureBridgeClientStore(),
  );
  try {
    await server.start();
  } catch (e) {
    debugPrint('Browser bridge unavailable: $e');
  }
  return server;
}

TrayLabels _trayLabels(LanguageSettings language) {
  final strings = lookupAppLocalizations(
    language.locale ??
        basicLocaleListResolution(
          WidgetsBinding.instance.platformDispatcher.locales,
          AppLocalizations.supportedLocales,
        ),
  );
  return TrayLabels(
    tooltip: 'Arcanum',
    open: strings.trayOpen,
    lock: strings.trayLock,
    quit: strings.trayQuit,
  );
}

/// Keeps the app in the tray once the window is closed, desktop only.
Future<BackgroundMode?> _startBackgroundMode({
  required VaultController controller,
  required BridgeServer? bridge,
  required LanguageSettings language,
  required bool startHidden,
}) async {
  if (!_isDesktop) return null;
  final dir = await getApplicationSupportDirectory();
  final mode = BackgroundMode(
    window: DesktopAppWindow(),
    tray: DesktopSystemTray(),
    loginItem: DesktopLoginItem.create() ?? const NoLoginItem(),
    store: FileBackgroundPrefsStore('${dir.path}/background.json'),
    onLock: controller.lock,
    onQuit: () async => bridge?.stop(),
  );
  await mode.init(labels: _trayLabels(language), startHidden: startHidden);
  language.addListener(() => mode.setLabels(_trayLabels(language)));
  return mode;
}

Future<void> main(List<String> args) async {
  final controller = await _openVault();
  final language = await _loadLanguage();
  language.addListener(
    () => AndroidLanguage.apply(language.locale?.languageCode),
  );
  final breach = await _loadBreachChecker();
  final favicons = await _loadFavicons();
  await QuickAccess.init();
  final bridge = await _startBrowserBridge(controller);
  final background = await _startBackgroundMode(
    controller: controller,
    bridge: bridge,
    language: language,
    // Passed by the login item; the native runner then leaves the window
    // hidden.
    startHidden: args.contains('--hidden'),
  );
  runApp(
    ArcanumApp(
      controller: controller,
      language: language,
      breach: breach,
      favicons: favicons,
      bridge: bridge,
      background: background,
    ),
  );
}

/// Entry point used by Android's AutofillActivity.
@pragma('vm:entry-point')
Future<void> autofillMain() async {
  final controller = await _openVault();
  final bridge = ChannelAutofillBridge();
  final request = await bridge.request();
  final language = await _loadLanguage();
  runApp(
    AutofillApp(
      controller: controller,
      bridge: bridge,
      request: request,
      language: language,
    ),
  );
}
