import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/language_settings.dart';
import 'package:arcanum/app/messages.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/src/rust/api/vault.dart';
import 'package:arcanum/ui/app.dart';

import 'fakes.dart';
import 'window.dart';

Future<VaultController> _controller() async {
  final controller = VaultController(
    handle: FakeVaultHandle(),
    secretKeys: MemorySecretKeyStore(),
    quickUnlock: FakeQuickUnlockStore(available: false),
  );
  await controller.init();
  return controller;
}

const _wrongCredentials = VaultFailure(
  code: VaultFailureCode.wrongCredentials,
  message: '',
);

void main() {
  testWidgets('the picked language is applied and saved', (tester) async {
    final store = MemoryLanguageStore();
    final language = LanguageSettings(store: store);
    useNarrowWindow(tester);
    await tester.pumpWidget(
      ArcanumApp(controller: await _controller(), language: language),
    );

    // The test device is Italian and nothing is picked yet.
    expect(find.text('Crea il tuo vault'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.translate));
    await tester.pumpAndSettle();
    expect(find.text('Predefinita di sistema'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('Create your vault'), findsOneWidget);
    expect(store.value, 'en');
    // Messages built outside widgets follow the UI language too.
    expect(failureMessage(_wrongCredentials), startsWith('Wrong master'));

    // Back to the system language.
    await tester.tap(find.byIcon(Icons.translate));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();

    expect(find.text('Crea il tuo vault'), findsOneWidget);
    expect(store.value, isNull);
  });

  testWidgets('a saved language is restored at startup', (tester) async {
    final language = LanguageSettings(
      store: MemoryLanguageStore()..value = 'en',
    );
    await language.load();
    useNarrowWindow(tester);
    await tester.pumpWidget(
      ArcanumApp(controller: await _controller(), language: language),
    );

    expect(find.text('Create your vault'), findsOneWidget);
  });

  test('an unknown saved language falls back to the system', () async {
    final language = LanguageSettings(
      store: MemoryLanguageStore()..value = 'xx',
    );
    await language.load();
    expect(language.locale, isNull);
  });
}
