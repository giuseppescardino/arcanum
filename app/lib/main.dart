import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/android_language.dart';
import 'app/breach_check.dart';
import 'app/favicons.dart';
import 'app/language_settings.dart';
import 'app/quick_access.dart';
import 'app/secret_key_store.dart';
import 'app/vault_controller.dart';
import 'autofill/autofill_app.dart';
import 'autofill/autofill_bridge.dart';
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

Future<void> main() async {
  final controller = await _openVault();
  final language = await _loadLanguage();
  language.addListener(
    () => AndroidLanguage.apply(language.locale?.languageCode),
  );
  final breach = await _loadBreachChecker();
  final favicons = await _loadFavicons();
  await QuickAccess.init();
  runApp(
    ArcanumApp(
      controller: controller,
      language: language,
      breach: breach,
      favicons: favicons,
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
