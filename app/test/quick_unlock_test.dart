import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/src/rust/api/vault.dart';
import 'package:arcanum/ui/app.dart';

import 'fake_tools.dart';
import 'fakes.dart';

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

  testWidgets('menu toggles quick unlock', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
