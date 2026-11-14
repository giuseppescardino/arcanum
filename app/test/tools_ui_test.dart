import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/src/rust/api/vault.dart';
import 'package:arcanum/ui/app.dart';

import 'fake_tools.dart';
import 'fakes.dart';
import 'window.dart';

void main() {
  setUp(() => tools = FakeTools());

  Future<VaultController> openVault(WidgetTester tester) async {
    useNarrowWindow(tester, height: 1000);
    final controller = VaultController(
      handle: FakeVaultHandle(),
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: FakeQuickUnlockStore(available: false),
    );
    await controller.create('master-password');
    controller.confirmEmergencyKit();
    await tester.pumpWidget(ArcanumApp(controller: controller));
    return controller;
  }

  testWidgets('generator fills the password field', (tester) async {
    final controller = await openVault(tester);
    await tester.tap(find.text('Nuovo'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Genera'));
    await tester.pumpAndSettle();
    expect(find.text('Genera password'), findsOneWidget);

    // Switching to passphrase regenerates the value.
    await tester.tap(find.text('Passphrase'));
    await tester.pumpAndSettle();
    final shown = tester
        .widget<SelectableText>(find.byKey(const ValueKey('generated-value')))
        .data!;
    expect(shown, contains('word'));

    await tester.tap(find.text('Usa'));
    await tester.pumpAndSettle();
    expect(find.text(shown), findsOneWidget);
    expect(find.textContaining('bit'), findsOneWidget, reason: 'meter');

    await tester.enterText(find.byType(TextFormField).at(0), 'Site');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(controller.items.single.fields.password, shown);
    controller.dispose();
  });

  testWidgets('invalid TOTP is rejected, valid one shows a code', (
    tester,
  ) async {
    final controller = await openVault(tester);
    await tester.tap(find.text('Nuovo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Mail');

    final totpField = find.widgetWithText(TextFormField, 'Chiave 2FA (TOTP)');
    await tester.enterText(totpField, 'nope');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Chiave 2FA non valida'), findsOneWidget);

    await tester.enterText(totpField, 'JBSWY3DPEHPK3PXP');
    await tester.pump();
    expect(find.text('123 456'), findsOneWidget);

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(controller.items.single.fields.totp, 'JBSWY3DPEHPK3PXP');
    expect(find.byTooltip('Copia codice 2FA'), findsOneWidget);
    controller.dispose();
  });

  test('fake tools keep the ItemFields contract', () {
    expect(
      const ItemFields(
        kind: VaultItemKind.login,
        title: '',
        username: '',
        password: '',
        urls: [],
        notes: '',
        favorite: false,
        group: '',
        color: null,
      ).totp,
      isNull,
    );
  });
}
