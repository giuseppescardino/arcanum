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
  late FakeVaultHandle handle;
  late FakeQuickUnlockStore store;
  late VaultController controller;

  setUp(() {
    tools = FakeTools();
    handle = FakeVaultHandle();
    store = FakeQuickUnlockStore();
    controller = VaultController(
      handle: handle,
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: store,
    );
  });

  tearDown(() => controller.dispose());

  Future<void> createUnlocked() async {
    await controller.init();
    await controller.create('master-password');
    controller.confirmEmergencyKit();
  }

  test('enable, lock, unlock with biometrics', () async {
    await createUnlocked();
    expect(controller.quickUnlockAvailable, isTrue);
    await controller.enableQuickUnlock();
    expect(controller.quickUnlockEnabled, isTrue);
    expect(store.stored, handle.quickSecret);

    controller.lock();
    expect(await controller.unlockWithBiometrics(), isTrue);
    expect(controller.stage, VaultStage.unlocked);
  });

  test('cancelled prompt keeps the vault locked', () async {
    await createUnlocked();
    await controller.enableQuickUnlock();
    controller.lock();
    store.cancel = true;
    expect(await controller.unlockWithBiometrics(), isFalse);
    expect(controller.stage, VaultStage.locked);
  });

  test('stale secret disables quick unlock', () async {
    await createUnlocked();
    await controller.enableQuickUnlock();
    controller.lock();
    store.stored = 'something else';
    await expectLater(
      controller.unlockWithBiometrics(),
      throwsA(isA<VaultFailure>()),
    );
    expect(controller.quickUnlockEnabled, isFalse);
    expect(store.stored, isNull);
  });

  test('password required keeps quick unlock configured', () async {
    await createUnlocked();
    await controller.enableQuickUnlock();
    controller.lock();
    handle.nextQuickFailure = const VaultFailure(
      code: VaultFailureCode.passwordRequired,
      message: '',
    );
    await expectLater(
      controller.unlockWithBiometrics(),
      throwsA(isA<VaultFailure>()),
    );
    expect(controller.quickUnlockEnabled, isTrue);
  });

  test('disable removes the stored secret', () async {
    await createUnlocked();
    await controller.enableQuickUnlock();
    await controller.disableQuickUnlock();
    expect(controller.quickUnlockEnabled, isFalse);
    expect(store.stored, isNull);
    expect(await handle.hasQuickUnlock(), isFalse);
  });

  testWidgets('unlock screen prompts for biometrics automatically', (
    tester,
  ) async {
    await createUnlocked();
    await controller.enableQuickUnlock();
    controller.lock();

    await tester.pumpWidget(ArcanumApp(controller: controller));
    await tester.pumpAndSettle();
    expect(store.prompts, 1);
    expect(controller.stage, VaultStage.unlocked);
    expect(find.text('Vault'), findsOneWidget);
    controller.lock(); // stop the auto-lock timer
  });

  Future<void> moveTo(
    WidgetTester tester,
    List<AppLifecycleState> states,
  ) async {
    for (final s in states) {
      tester.binding.handleAppLifecycleStateChanged(s);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  const toBackground = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const toForeground = [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  testWidgets('returning to the app prompts for biometrics again', (
    tester,
  ) async {
    store.foregroundOnly = true;
    await createUnlocked();
    await controller.enableQuickUnlock();
    await tester.pumpWidget(ArcanumApp(controller: controller));
    expect(controller.stage, VaultStage.unlocked);

    // Leaving locks the vault; the system can't prompt in background.
    await moveTo(tester, toBackground);
    expect(controller.stage, VaultStage.locked);
    expect(store.prompts, 0);

    await moveTo(tester, toForeground);
    expect(store.prompts, 1);
    expect(controller.stage, VaultStage.unlocked);

    await tester.pumpWidget(const SizedBox());
    controller.lock();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a cancelled prompt is not repeated by its own dismissal', (
    tester,
  ) async {
    await createUnlocked();
    await controller.enableQuickUnlock();
    controller.lock();
    store.cancel = true;
    await tester.pumpWidget(ArcanumApp(controller: controller));
    await tester.pumpAndSettle();
    expect(store.prompts, 1);

    // The Face ID sheet only makes the app inactive.
    await moveTo(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(store.prompts, 1);

    // A real trip to the background asks again.
    await moveTo(tester, [...toBackground, ...toForeground]);
    expect(store.prompts, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('menu toggles quick unlock', (tester) async {
    useNarrowWindow(tester);
    await createUnlocked();
    await tester.pumpWidget(ArcanumApp(controller: controller));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attiva sblocco con Test Biometrics'));
    await tester.pumpAndSettle();
    expect(controller.quickUnlockEnabled, isTrue);
    // Unmount first: a locked vault would re-prompt and unlock again.
    await tester.pumpWidget(const SizedBox());
    controller.lock();
  });
}
