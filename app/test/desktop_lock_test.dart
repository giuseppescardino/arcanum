import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/background_mode.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/ui/app.dart';

import 'fake_tools.dart';
import 'fakes.dart';

/// Desktop windows get minimized, closed to the tray and restored all the
/// time: none of that may lock the vault or open the biometric prompt
/// (Windows Hello, Touch ID). Only the inactivity timer and the user lock.
void main() {
  const autoLock = Duration(minutes: 5);
  final desktop = TargetPlatformVariant.desktop();

  late FakeQuickUnlockStore store;
  late VaultController controller;

  setUp(() {
    tools = FakeTools();
    store = FakeQuickUnlockStore();
    controller = VaultController(
      handle: FakeVaultHandle(),
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: store,
      autoLockAfter: autoLock,
    );
  });

  tearDown(() => controller.dispose());

  Future<void> createWithQuickUnlock() async {
    await controller.init();
    await controller.create('master-password');
    controller.confirmEmergencyKit();
    await controller.enableQuickUnlock();
  }

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

  // Minimized or closed to the tray (the engine may also report paused).
  const minimize = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const restore = [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  /// Puts the binding back the way the next test expects it.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.lock(); // stop the auto-lock timer
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  testWidgets('minimizing and restoring keeps the vault unlocked', (
    tester,
  ) async {
    await createWithQuickUnlock();
    await tester.pumpWidget(ArcanumApp(controller: controller));

    await moveTo(tester, minimize);
    expect(controller.stage, VaultStage.unlocked);
    await moveTo(tester, restore);
    expect(controller.stage, VaultStage.unlocked);
    expect(store.prompts, 0);
    await unmount(tester);
  }, variant: desktop);

  testWidgets('restoring a locked window does not open the prompt', (
    tester,
  ) async {
    await createWithQuickUnlock();
    controller.lock();
    store.cancel = true;
    await tester.pumpWidget(ArcanumApp(controller: controller));
    await tester.pumpAndSettle();
    expect(store.prompts, 1, reason: 'offered once at launch');

    for (var i = 0; i < 3; i++) {
      await moveTo(tester, minimize);
      await moveTo(tester, restore);
    }
    expect(store.prompts, 1);
    expect(controller.stage, VaultStage.locked);
    await unmount(tester);
  }, variant: desktop);

  testWidgets('the inactivity lock still runs while the window is hidden', (
    tester,
  ) async {
    await createWithQuickUnlock();
    await tester.pumpWidget(ArcanumApp(controller: controller));

    await moveTo(tester, minimize);
    await tester.pump(autoLock + const Duration(seconds: 1));
    expect(controller.stage, VaultStage.locked);
    expect(store.prompts, 0, reason: 'no prompt from a hidden window');

    await moveTo(tester, restore);
    expect(store.prompts, 0);
    expect(controller.stage, VaultStage.locked);
    await unmount(tester);
  }, variant: desktop);

  testWidgets('after a lock the prompt opens from its button only', (
    tester,
  ) async {
    await createWithQuickUnlock();
    await tester.pumpWidget(ArcanumApp(controller: controller));

    controller.lock();
    await tester.pumpAndSettle();
    expect(store.prompts, 0);

    await tester.tap(find.text('Sblocca con Test Biometrics'));
    await tester.pumpAndSettle();
    expect(store.prompts, 1);
    expect(controller.stage, VaultStage.unlocked);
    await unmount(tester);
  }, variant: desktop);

  testWidgets('a hidden start at login does not open the prompt', (
    tester,
  ) async {
    await createWithQuickUnlock();
    controller.lock();
    final background = BackgroundMode(
      window: FakeAppWindow(),
      tray: FakeSystemTray(),
      loginItem: FakeLoginItem(),
      onLock: controller.lock,
      onQuit: () async {},
    );
    await background.init(labels: _labels, startHidden: true);
    expect(background.startedHidden, isTrue);

    await tester.pumpWidget(
      ArcanumApp(controller: controller, background: background),
    );
    await tester.pumpAndSettle();
    await moveTo(tester, restore);
    expect(store.prompts, 0);
    await unmount(tester);
  }, variant: desktop);

  testWidgets('a mobile app still locks and prompts when it comes back', (
    tester,
  ) async {
    await createWithQuickUnlock();
    await tester.pumpWidget(ArcanumApp(controller: controller));

    await moveTo(tester, minimize);
    expect(controller.stage, VaultStage.locked);
    await moveTo(tester, restore);
    expect(store.prompts, 1);
    expect(controller.stage, VaultStage.unlocked);
    await unmount(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

const _labels = TrayLabels(
  tooltip: 'Arcanum',
  open: 'Open Arcanum',
  lock: 'Lock',
  quit: 'Quit',
);
