import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/expiry.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/src/rust/api/vault.dart';
import 'package:arcanum/ui/app.dart';

import 'fake_tools.dart';
import 'fakes.dart';
import 'window.dart';

const _helper =
    'Facoltativa. La voce viene segnalata quando la data si avvicina.';

ItemFields _card(String expiry) => ItemFields(
  kind: VaultItemKind.card,
  title: 'Carta',
  username: '',
  password: '',
  urls: const [],
  notes: '',
  favorite: false,
  group: '',
  color: null,
  card: CardFields(
    holder: 'A',
    number: '4111111111111111',
    expiry: expiry,
    cvv: '',
    pin: '',
  ),
);

void main() {
  final now = DateTime(2026, 11, 13, 15, 30);

  test('states around the 30-day window', () {
    ExpiryState of(String? d) => expiryState(login('x', expiresOn: d), now);
    expect(of(null), ExpiryState.none);
    expect(of('2026-11-12'), ExpiryState.expired);
    expect(of('2026-11-13'), ExpiryState.soon); // today still counts
    expect(of('2026-12-13'), ExpiryState.soon); // day 30
    expect(of('2026-12-14'), ExpiryState.ok); // day 31
  });

  test('bad dates mean no expiry', () {
    for (final bad in ['', '2026-02-30', '13/11/2026', 'soon']) {
      expect(expiryOf(login('x', expiresOn: bad)), isNull, reason: bad);
    }
  });

  test('a card expires on the last day of its month', () {
    expect(expiryOf(_card('02/28')), DateTime(2028, 2, 29));
    expect(expiryState(_card('10/26'), now), ExpiryState.expired);
    expect(expiryState(_card('11/26'), now), ExpiryState.soon);
    expect(expiryOf(_card('')), isNull);
    expect(expiryOf(_card('13/26')), isNull);
  });

  test(
    'formatExpiry pads',
    () => expect(formatExpiry(DateTime(2027, 1, 5)), '2027-01-05'),
  );

  group('widgets', () {
    setUp(() => tools = FakeTools());

    Future<VaultController> unlocked() async {
      final c = VaultController(
        handle: FakeVaultHandle(),
        secretKeys: MemorySecretKeyStore(),
        quickUnlock: FakeQuickUnlockStore(available: false),
      );
      await c.create('master-password');
      c.confirmEmergencyKit();
      return c;
    }

    void desktop(WidgetTester tester) {
      useNarrowWindow(tester);
    }

    testWidgets('the editor sets and clears the expiry', (tester) async {
      desktop(tester);
      final c = await unlocked();
      await tester.pumpWidget(ArcanumApp(controller: c));
      await tester.tap(find.text('Nuovo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Titolo'),
        'Sito',
      );
      await tester.tap(find.widgetWithText(TextFormField, 'Scadenza'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();
      expect(c.items.single.fields.expiresOn, isNotNull);

      await tester.tap(find.text('Sito'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modifica'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rimuovi scadenza'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();
      expect(c.items.single.fields.expiresOn, isNull);
      c.dispose();
    });

    testWidgets('the calendar button opens the picker', (tester) async {
      desktop(tester);
      final c = await unlocked();
      await tester.pumpWidget(ArcanumApp(controller: c));
      await tester.tap(find.text('Nuovo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Scadenza'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      c.dispose();
    });

    testWidgets('an out-of-range stored expiry still opens the picker', (
      tester,
    ) async {
      desktop(tester);
      final c = await unlocked();
      await c.save(login('Old', expiresOn: '1990-01-01'));
      await tester.pumpWidget(ArcanumApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Old'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modifica'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Scadenza'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      c.dispose();
    });

    testWidgets('a card item has no expiry field', (tester) async {
      desktop(tester);
      final c = await unlocked();
      await tester.pumpWidget(ArcanumApp(controller: c));
      await tester.tap(find.text('Nuovo'));
      await tester.pumpAndSettle();
      // A login shows the new control.
      expect(find.text(_helper), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Carta'));
      await tester.pumpAndSettle();
      // The card's own MM/AA field is there, the new control is not.
      expect(find.byKey(const Key('cardExpiry')), findsOneWidget);
      expect(find.text(_helper), findsNothing);
      c.dispose();
    });

    testWidgets('rows flag expired and expiring items', (tester) async {
      desktop(tester);
      final c = await unlocked();
      final soon = formatExpiry(DateTime.now().add(const Duration(days: 5)));
      await c.save(login('Old', expiresOn: '2020-01-01'));
      await c.save(login('Soon', expiresOn: soon));
      await c.save(login('Fine'));
      await tester.pumpWidget(ArcanumApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Scaduta'), findsOneWidget);
      expect(find.byTooltip('In scadenza'), findsOneWidget);
      c.dispose();
    });
  });
}
