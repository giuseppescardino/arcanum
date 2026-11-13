import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/cards.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/src/rust/api/vault.dart';
import 'package:arcanum/ui/app.dart';

import 'fake_tools.dart';
import 'fakes.dart';
import 'window.dart';

void main() {
  setUp(() => tools = FakeTools());

  late VaultController controller;
  String? clipboard;

  Future<void> pumpApp(
    WidgetTester tester,
    List<ItemFields> items,
  ) async {
    useNarrowWindow(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        return null;
      },
    );
    controller = VaultController(
      handle: FakeVaultHandle(),
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: FakeQuickUnlockStore(available: false),
    );
    await controller.create('master-password');
    controller.confirmEmergencyKit();
    for (final f in items) {
      await controller.save(f);
    }
    await tester.pumpWidget(ArcanumApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.lock();
    // Let a pending clipboard-clearing timer fire.
    await tester.pump(const Duration(seconds: 31));
    controller.dispose();
  }

  Future<void> openBank(WidgetTester tester) async {
    await pumpApp(tester, [
      login(
        'Bank',
        username: 'alice',
        password: 'top-secret',
        expiresOn: '2020-01-01',
      ),
    ]);
    await tester.tap(find.text('Bank'));
    await tester.pumpAndSettle();
  }

  testWidgets('opening an item shows it read-only with its dates', (
    tester,
  ) async {
    await openBank(tester);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('top-secret'), findsNothing); // masked
    expect(find.text('Modificata il 13/11/2026'), findsOneWidget);
    expect(find.text('Scaduta il 01/01/2020'), findsOneWidget);
    expect(find.text('Salva'), findsNothing);
    await unmount(tester);
  });

  testWidgets('reveal shows the password, copy copies it', (tester) async {
    await openBank(tester);
    await tester.tap(find.byTooltip('Mostra'));
    await tester.pump();
    expect(find.text('top-secret'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('${controller.items.single.id}/password')),
        matching: find.byTooltip('Copia'),
      ),
    );
    await tester.pump();
    expect(clipboard, 'top-secret');
    await unmount(tester);
  });

  testWidgets('Modifica opens the editor and a save comes back updated', (
    tester,
  ) async {
    await openBank(tester);
    await tester.tap(find.text('Modifica'));
    await tester.pumpAndSettle();
    expect(find.text('Salva'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome utente / email'),
      'bob',
    );
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNothing); // back on the view
    expect(find.text('bob'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('deleting from the editor closes the view too', (tester) async {
    await openBank(tester);
    await tester.tap(find.text('Modifica'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Elimina'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Elimina'));
    await tester.pumpAndSettle();

    expect(find.text('Modifica'), findsNothing);
    expect(find.textContaining('Il vault è vuoto'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('a sync removing the open item closes the view', (tester) async {
    await openBank(tester);
    expect(find.text('Modifica'), findsOneWidget);
    await tester.runAsync(() => controller.delete(controller.items.single.id));
    await tester.pumpAndSettle();

    expect(find.text('Modifica'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('card and wifi items show their details', (tester) async {
    await pumpApp(tester, [
      ItemFields(
        kind: VaultItemKind.card,
        title: 'Visa',
        username: '',
        password: '',
        urls: const [],
        notes: '',
        favorite: false,
        group: '',
        color: null,
        card: const CardFields(
          holder: 'Alice Rossi',
          number: '4111111111111111',
          expiry: '12/30',
          cvv: '987',
          pin: '',
        ),
      ),
      ItemFields(
        kind: VaultItemKind.wifi,
        title: 'Casa',
        username: '',
        password: 'wifi-pass',
        urls: const [],
        notes: '',
        favorite: false,
        group: '',
        color: null,
        wifi: const WifiFields(
          ssid: 'HomeNet',
          security: WifiSecurityKind.wpa,
          hidden: false,
        ),
      ),
    ]);

    await tester.tap(find.text('Visa'));
    await tester.pumpAndSettle();
    expect(find.text('Alice Rossi'), findsOneWidget);
    expect(find.text(maskCardNumber('4111111111111111')), findsOneWidget);
    expect(find.text('987'), findsNothing);
    expect(find.text('12/30'), findsOneWidget);
    Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Casa'));
    await tester.pumpAndSettle();
    expect(find.text('HomeNet'), findsOneWidget);
    expect(find.text('wifi-pass'), findsNothing);
    expect(find.text('Mostra codice QR'), findsOneWidget);
    await unmount(tester);
  });
}
