import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/quick_access.dart';
import 'app/secret_key_store.dart';
import 'app/vault_controller.dart';
import 'autofill/autofill_app.dart';
import 'autofill/autofill_bridge.dart';
import 'src/rust/api/vault.dart';
import 'src/rust/frb_generated.dart';
import 'ui/app.dart';

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
  await QuickAccess.init();
  runApp(ArcanumApp(controller: controller));
}

/// Entry point used by Android's AutofillActivity.
@pragma('vm:entry-point')
Future<void> autofillMain() async {
  final controller = await _openVault();
  final bridge = ChannelAutofillBridge();
  final request = await bridge.request();
  runApp(AutofillApp(controller: controller, bridge: bridge, request: request));
}
