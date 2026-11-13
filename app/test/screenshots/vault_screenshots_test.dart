// Renders the vault to PNG files for a visual check of the theme. Off by
// default; run with
//   SHOT_DIR=<folder> flutter test test/screenshots
// on Windows (it loads Segoe UI from C:\Windows\Fonts).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/src/rust/api/vault.dart';
import 'package:arcanum/ui/app.dart';

import '../fake_tools.dart';
import '../fakes.dart';

final _outDir = Platform.environment['SHOT_DIR'];

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final bytes = File(p).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  const win = r'C:\Windows\Fonts';
  await _loadFont('Segoe UI', [
    '$win\\segoeui.ttf',
    '$win\\segoeuib.ttf',
    '$win\\segoeuisl.ttf',
    '$win\\seguisb.ttf',
  ]);
  await _loadFont('monospace', ['$win\\consola.ttf']);
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  await _loadFont('MaterialIcons', [
    '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  ]);
}

Future<VaultController> _vault() async {
  final controller = VaultController(
    handle: FakeVaultHandle(),
    secretKeys: MemorySecretKeyStore(),
    quickUnlock: FakeQuickUnlockStore(available: false),
  );
  await controller.create('master-password');
  controller.confirmEmergencyKit();
  final soon = DateTime.now().add(const Duration(days: 9));
  String day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final items = <ItemFields>[
    login(
      'PayPal',
      username: 'mario.rossi@gmail.com',
      favorite: true,
      group: 'Personale',
      password: 'Xk9#pL2!vQ7@mN4z',
      urls: ['https://paypal.com'],
    ),
    login(
      'GitHub',
      username: 'mario.rossi@outlook.com',
      favorite: true,
      group: 'Personale/Develop',
      urls: ['https://github.com'],
    ),
    login(
      'Aruba',
      username: '751281@aruba.it',
      group: 'Personale/Develop',
      expiresOn: '2025-01-31',
    ),
    login('Mega', username: 'mario.rossi@gmail.com', group: 'Personale'),
    login(
      'PEC',
      username: 'mario.rossi@pec.it',
      group: 'Personale',
      expiresOn: day(soon),
    ),
    login('Centralino', username: 'centralino@azienda.it', group: 'Lavoro'),
    login('Google account', username: 'info@azienda.it', group: 'Lavoro'),
    login('Infobip', username: 'userfidelia', group: 'Lavoro'),
    login('Campus', username: 'm.rossi', group: 'Campus'),
    login('Tiscali', username: 'g.rossi@tiscali.it'),
  ];
  for (final f in items) {
    await controller.save(f);
  }
  await controller.setGroupColor('Lavoro', 0xFF3949AB);
  await controller.setGroupColor('Campus', 0xFF7CB342);
  return controller;
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final element = find.byType(MaterialApp).evaluate().single;
  await tester.runAsync(() async {
    final image = await captureImage(element);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  if (_outDir == null) {
    test('screenshots (set SHOT_DIR to render)', () {}, skip: true);
    return;
  }
  setUp(() => tools = FakeTools());

  Future<VaultController> open(
    WidgetTester tester,
    Size size, {
    Brightness brightness = Brightness.light,
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    });
    await tester.runAsync(_loadFonts);
    final controller = await _vault();
    await tester.pumpWidget(ArcanumApp(controller: controller));
    await tester.pumpAndSettle();
    return controller;
  }

  for (final brightness in Brightness.values) {
    testWidgets('wide ${brightness.name}', (tester) async {
      final c = await open(
        tester,
        const Size(1280, 800),
        brightness: brightness,
      );
      await tester.tap(find.text('Personale').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('PayPal'));
      await _shot(tester, 'wide-${brightness.name}');
      c.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('wide all', (tester) async {
    final c = await open(tester, const Size(1280, 800));
    await _shot(tester, 'wide-all');
    c.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('narrow', (tester) async {
    final c = await open(tester, const Size(420, 860));
    await _shot(tester, 'narrow');
    await tester.tap(find.text('Personale').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('PayPal'));
    await _shot(tester, 'narrow-detail');
    c.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('settings', (tester) async {
    final c = await open(tester, const Size(1280, 800));
    await tester.tap(find.text('Impostazioni').first);
    await _shot(tester, 'settings');
    c.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
