import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/ui/app.dart';

import 'fake_tools.dart';
import 'fakes.dart';

void main() {
  setUp(() => tools = FakeTools());

  testWidgets('setup, emergency kit, add item, lock, unlock', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = VaultController(
      handle: FakeVaultHandle(),
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: FakeQuickUnlockStore(available: false),
    );
    await controller.init();
    await tester.pumpWidget(ArcanumApp(controller: controller));

    // Setup: validation, then create.
    expect(find.text('Crea il tuo vault'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'short');
    await tester.tap(find.text('Crea vault'));
    await tester.pump();
    expect(find.text('Almeno 10 caratteri'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'master-password');
    await tester.enterText(find.byType(TextFormField).at(1), 'master-password');
    await tester.tap(find.text('Crea vault'));
    await tester.pumpAndSettle();

    // Emergency Kit: Continue is disabled until the checkbox is ticked.
    expect(find.text(fakeSecretKey), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Continua'));
    await tester.pumpAndSettle();

    // Empty vault, add a login.
    expect(find.textContaining('Il vault è vuoto'), findsOneWidget);
    await tester.tap(find.text('Nuovo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'GitHub');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome utente / email'),
      'alice@example.com',
    );
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);

    // Search filters the list.
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pump();
    expect(find.text('Nessun risultato.'), findsOneWidget);

    // Lock wipes the list; unlocking with the stored key brings it back.
    await tester.tap(find.byTooltip('Blocca'));
    await tester.pumpAndSettle();
    expect(find.text('Sblocca il vault'), findsOneWidget);
    expect(find.text('GitHub'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, 'wrong');
    await tester.tap(find.text('Sblocca'));
    await tester.pumpAndSettle();
    expect(find.textContaining('errata'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'master-password');
    await tester.tap(find.text('Sblocca'));
    await tester.pumpAndSettle();
    expect(find.text('GitHub'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('locking closes an open editor', (tester) async {
    final controller = VaultController(
      handle: FakeVaultHandle(),
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: FakeQuickUnlockStore(available: false),
    );
    await controller.create('master-password');
    controller.confirmEmergencyKit();
    await controller.save(login('Bank', password: 'top-secret'));
    await tester.pumpWidget(ArcanumApp(controller: controller));

    await tester.tap(find.text('Bank'));
    await tester.pumpAndSettle();
    expect(find.text('Modifica'), findsOneWidget);

    controller.lock();
    await tester.pumpAndSettle();
    expect(find.text('Modifica'), findsNothing);
    expect(find.text('Sblocca il vault'), findsOneWidget);

    controller.dispose();
  });
}
