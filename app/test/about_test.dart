import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/ui/app.dart';

import 'fake_tools.dart';
import 'fakes.dart';
import 'window.dart';

void main() {
  late VaultController controller;

  setUp(() async {
    tools = FakeTools();
    PackageInfo.setMockInitialValues(
      appName: 'arcanum',
      packageName: 'it.arcanum',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
    );
    controller = VaultController(
      handle: FakeVaultHandle(),
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: FakeQuickUnlockStore(),
    );
    await controller.init();
    await controller.create('master-password');
    controller.confirmEmergencyKit();
  });

  tearDown(() => controller.dispose());

  Future<void> openAbout(WidgetTester tester, String entry) async {
    useNarrowWindow(tester);
    await tester.pumpWidget(ArcanumApp(controller: controller));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    await tester.tap(find.text(entry));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.lock(); // stop the auto-lock timer
  }

  testWidgets('menu opens About with the runtime version', (tester) async {
    await openAbout(tester, 'Informazioni');

    expect(find.byType(AboutDialog), findsOneWidget);
    expect(find.text('Arcanum'), findsWidgets);
    expect(find.text('Versione 1.2.3 (45)'), findsOneWidget);
    expect(
      find.textContaining('Password manager zero-knowledge'),
      findsOneWidget,
    );

    // Actions are "view licenses" then "close".
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(AboutDialog), findsNothing);
    await unmount(tester);
  });

  testWidgets('About is localized in English', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(
      () => tester.platformDispatcher.localesTestValue = const [Locale('it')],
    );
    await openAbout(tester, 'About');

    expect(find.text('Version 1.2.3 (45)'), findsOneWidget);
    expect(
      find.textContaining('Zero-knowledge password manager'),
      findsOneWidget,
    );
    await unmount(tester);
  });
}
