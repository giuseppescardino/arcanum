import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/favicons.dart';
import 'package:arcanum/app/file_dialogs.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/ui/app.dart';
import 'package:arcanum/ui/settings_screen.dart';

import 'fake_tools.dart';
import 'fakes.dart';
import 'window.dart';

class _NoSaveDialogs extends FakeFileDialogs {
  @override
  bool get canSave => false;
}

void main() {
  late VaultController controller;

  setUp(() {
    tools = FakeTools();
    fileDialogs = FakeFileDialogs();
    addTearDown(() => fileDialogs = const PlatformFileDialogs());
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    bool quickUnlock = false,
    FaviconCache? favicons,
  }) async {
    useNarrowWindow(tester);
    controller = VaultController(
      handle: FakeVaultHandle(),
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: FakeQuickUnlockStore(available: quickUnlock),
    );
    await tester.runAsync(() async {
      await controller.init();
      await controller.create('master-password');
      controller.confirmEmergencyKit();
    });
    await tester.pumpWidget(
      ArcanumApp(controller: controller, favicons: favicons),
    );
    await tester.pumpAndSettle();
  }

  /// Unmounts and locks so no timer outlives the test.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.lock();
    controller.dispose();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Impostazioni'));
    await tester.pumpAndSettle();
  }

  testWidgets('settings are grouped and the danger zone comes last', (
    tester,
  ) async {
    await pumpApp(tester);
    await openSettings(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);

    for (final s in [
      'Sicurezza',
      'Sincronizzazione',
      'Dati',
      'Aspetto',
      'Zona pericolosa',
    ]) {
      await tester.scrollUntilVisible(find.text(s), 200);
      expect(find.text(s), findsOneWidget);
    }
    final danger = tester.getTopLeft(find.text('Zona pericolosa')).dy;
    expect(
      tester.getTopLeft(find.text('Esci da questo dispositivo')).dy,
      greaterThan(danger),
    );
    expect(
      tester
          .getTopLeft(find.text('Rimuovi Secret Key da questo dispositivo'))
          .dy,
      greaterThan(danger),
    );
    await finish(tester);
  });

  testWidgets('entries follow availability', (tester) async {
    fileDialogs = _NoSaveDialogs();
    await pumpApp(tester);
    await openSettings(tester);

    expect(find.text('Sblocco con Test Biometrics'), findsNothing);
    expect(find.text('Browser collegati'), findsNothing);
    expect(find.text('Esporta…'), findsNothing);
    expect(find.text('Importa…'), findsOneWidget);
    expect(find.text('Cambia master password'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the quick unlock switch shows and flips the state', (
    tester,
  ) async {
    await pumpApp(tester, quickUnlock: true);
    await openSettings(tester);

    final tile = find.widgetWithText(
      SwitchListTile,
      'Sblocco con Test Biometrics',
    );
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(controller.quickUnlockEnabled, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    await finish(tester);
  });

  testWidgets('the site-icons switch toggles the preference', (tester) async {
    final cache = FaviconCache(fetch: (host) async => null);
    await pumpApp(tester, favicons: cache);
    await openSettings(tester);

    final tile = find.widgetWithText(SwitchListTile, 'Icone dei siti');
    await tester.scrollUntilVisible(tile, 200);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(cache.enabled, isFalse);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    await finish(tester);
  });

  testWidgets('sign out still asks for confirmation', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);

    final entry = find.text('Esci da questo dispositivo');
    await tester.scrollUntilVisible(entry, 200);
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.text('Uscire?'), findsOneWidget);

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(find.text('Uscire?'), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(controller.stage, VaultStage.unlocked);
    await finish(tester);
  });

  testWidgets('the vault screen has no popup menu', (tester) async {
    await pumpApp(tester);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byWidgetPredicate((w) => w is PopupMenuButton),
      ),
      findsNothing,
    );
    await finish(tester);
  });
}
