import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/cards.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/app/wifi_qr.dart';
import 'package:arcanum/src/rust/api/vault.dart';
import 'package:arcanum/ui/app.dart';

import 'fake_tools.dart';
import 'fakes.dart';
import 'window.dart';

void main() {
  group('card numbers', () {
    test('Luhn checksum', () {
      expect(luhnValid('4111 1111 1111 1111'), isTrue);
      expect(luhnValid('4111 1111 1111 1112'), isFalse);
      expect(luhnValid('79927398713'), isTrue);
      expect(luhnValid(''), isFalse);
    });

    test('networks from the leading digits', () {
      expect(cardBrand('4111111111111111'), CardBrand.visa);
      expect(cardBrand('5555555555554444'), CardBrand.mastercard);
      expect(cardBrand('2223003122003222'), CardBrand.mastercard);
      expect(cardBrand('378282246310005'), CardBrand.amex);
      expect(cardBrand('6011111111111117'), CardBrand.discover);
      expect(cardBrand('3530111333300000'), CardBrand.jcb);
      expect(cardBrand('30569309025904'), CardBrand.dinersClub);
      expect(cardBrand('6759649826438453'), CardBrand.maestro);
      expect(cardBrand('6200000000000005'), CardBrand.unionPay);
      expect(cardBrand('9999'), CardBrand.unknown);
    });

    test('problems: length per network, then checksum', () {
      expect(cardNumberProblem('4111 1111 1111 1111'), isNull);
      expect(cardNumberProblem('378282246310005'), isNull);
      expect(cardNumberProblem('4111'), CardNumberProblem.tooShort);
      // 15 digits is not a Visa length.
      expect(
        cardNumberProblem('411111111111111'),
        CardNumberProblem.wrongLength,
      );
      expect(cardNumberProblem('4111111111111112'), CardNumberProblem.checksum);
    });

    test('printed grouping and masking', () {
      expect(formatCardNumber('4111111111111111'), '4111 1111 1111 1111');
      expect(formatCardNumber('378282246310005'), '3782 822463 10005');
      expect(formatCardNumber('41111'), '4111 1');
      expect(maskCardNumber('4111111111111111'), '•••• 1111');
    });

    test('expiry', () {
      final now = DateTime(2026, 11, 10);
      expect(cardExpiryProblem('11/26', now: now), isNull);
      expect(cardExpiryProblem('10/26', now: now), CardExpiryProblem.expired);
      expect(cardExpiryProblem('13/27', now: now), CardExpiryProblem.format);
      expect(cardExpiryProblem('abc', now: now), CardExpiryProblem.format);
      expect(normalizeExpiry('8/2029'), '08/29');
    });
  });

  test('Wi-Fi QR payload escapes special characters', () {
    expect(
      wifiQrPayload(
        ssid: 'Casa; "5G"',
        security: WifiSecurityKind.wpa,
        password: r'a:b,c\d',
      ),
      r'WIFI:T:WPA;S:Casa\; \"5G\";P:a\:b\,c\\d;;',
    );
    expect(
      wifiQrPayload(
        ssid: 'Ospiti',
        security: WifiSecurityKind.none,
        password: 'ignored',
        hidden: true,
      ),
      'WIFI:T:nopass;S:Ospiti;H:true;;',
    );
  });

  group('editor', () {
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
      useNarrowWindow(tester, height: 1400);
    }

    testWidgets('a Wi-Fi item is saved and shows its QR code', (tester) async {
      desktop(tester);
      final c = await unlocked();
      await tester.pumpWidget(ArcanumApp(controller: c));
      await tester.tap(find.text('Nuovo'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Wi-Fi'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Titolo'),
        'Casa',
      );
      await tester.enterText(find.byKey(const Key('wifiSsid')), 'CasaNet');
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'pw-casa-123',
      );
      await tester.tap(find.text('Mostra codice QR'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wifiQr')), findsOneWidget);
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();
      final f = c.items.single.fields;
      expect(f.kind, VaultItemKind.wifi);
      expect(f.wifi!.ssid, 'CasaNet');
      expect(f.wifi!.security, WifiSecurityKind.wpa);
      expect(f.password, 'pw-casa-123');
      expect(find.text('CasaNet'), findsOneWidget);
      expect(find.byTooltip('Mostra QR Wi-Fi'), findsOneWidget);
      c.dispose();
    });

    testWidgets('an invalid card number blocks saving', (tester) async {
      desktop(tester);
      final c = await unlocked();
      await tester.pumpWidget(ArcanumApp(controller: c));
      await tester.tap(find.text('Nuovo'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Carta'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Titolo'),
        'Visa',
      );
      await tester.enterText(
        find.byKey(const Key('cardNumber')),
        '4111111111111112',
      );
      await tester.pump();
      // Typed digits are grouped as on the card.
      expect(find.text('4111 1111 1111 1112'), findsOneWidget);
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();
      expect(
        find.text('Numero non valido: controlla le cifre.'),
        findsOneWidget,
      );
      expect(c.items, isEmpty);

      await tester.enterText(
        find.byKey(const Key('cardNumber')),
        '4111111111111111',
      );
      await tester.enterText(find.byKey(const Key('cardExpiry')), '0829');
      await tester.pump();
      expect(find.text('Visa · numero valido'), findsOneWidget);
      expect(find.text('08/29'), findsOneWidget);
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      final card = c.items.single.fields.card!;
      expect(card.number, '4111111111111111');
      expect(card.expiry, '08/29');
      expect(find.text('Visa · •••• 1111 · scad. 08/29'), findsOneWidget);
      c.dispose();
    });
  });
}
