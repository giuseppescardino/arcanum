import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/src/rust/api/vault.dart';

import 'fakes.dart';

void main() {
  late FakeVaultHandle handle;
  late MemorySecretKeyStore keys;
  late VaultController controller;

  setUp(() {
    handle = FakeVaultHandle();
    keys = MemorySecretKeyStore();
    controller = VaultController(
      handle: handle,
      secretKeys: keys,
      quickUnlock: FakeQuickUnlockStore(available: false),
      syncDebounce: const Duration(milliseconds: 20),
      deviceName: () => 'Test device',
    );
  });

  tearDown(() => controller.dispose());

  Future<void> createUnlocked() async {
    await controller.create('master-password');
    controller.confirmEmergencyKit();
  }

  test('enable sync links the vault', () async {
    await createUnlocked();
    expect(controller.linked, isFalse);

    await controller.enableSync(
      serverUrl: 'https://sync.example',
      email: 'a@example.com',
      password: 'master-password',
    );
    expect(controller.linked, isTrue);
    expect(controller.syncInfo?.email, 'a@example.com');
    expect(controller.lastSync, isNotNull);
  });

  test('enable sync with wrong password fails and stays unlinked', () async {
    await createUnlocked();
    await expectLater(
      controller.enableSync(
        serverUrl: 'https://sync.example',
        email: 'a@example.com',
        password: 'nope',
      ),
      throwsA(isA<VaultFailure>()),
    );
    expect(controller.linked, isFalse);
  });

  test('sign in on a new device unlocks and stores the secret key', () async {
    await controller.init();
    expect(controller.stage, VaultStage.setup);

    await controller.signIn(
      serverUrl: 'https://sync.example',
      email: 'a@example.com',
      password: 'master-password',
      secretKey: fakeSecretKey,
    );
    expect(controller.stage, VaultStage.unlocked);
    expect(controller.linked, isTrue);
    expect(keys.value, fakeSecretKey);
  });

  test('edits trigger a debounced sync when linked', () async {
    await createUnlocked();
    await controller.save(login('A'));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(handle.syncCalls, 0, reason: 'not linked yet');

    await controller.enableSync(
      serverUrl: 'https://sync.example',
      email: 'a@example.com',
      password: 'master-password',
    );
    await controller.save(login('B'));
    await controller.save(login('C'));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(handle.syncCalls, 1, reason: 'two quick edits, one sync');
  });

  test('unlock of a linked vault syncs right away', () async {
    await createUnlocked();
    await controller.enableSync(
      serverUrl: 'https://sync.example',
      email: 'a@example.com',
      password: 'master-password',
    );
    controller.lock();
    await controller.unlock('master-password');
    await Future<void>.delayed(Duration.zero);
    expect(handle.syncCalls, 1);
  });

  test('expired session is reported and fixed by reconnect', () async {
    await createUnlocked();
    await controller.enableSync(
      serverUrl: 'https://sync.example',
      email: 'a@example.com',
      password: 'master-password',
    );
    handle.nextSyncFailure = const VaultFailure(
      code: VaultFailureCode.sessionExpired,
      message: '',
    );
    await controller.syncNow();
    expect(controller.sessionExpired, isTrue);
    expect(controller.syncError, contains('riconnetti'));

    await controller.reconnect('new-password');
    expect(controller.sessionExpired, isFalse);
    expect(controller.syncError, isNull);
  });

  test('network errors do not throw and are shown', () async {
    await createUnlocked();
    await controller.enableSync(
      serverUrl: 'https://sync.example',
      email: 'a@example.com',
      password: 'master-password',
    );
    handle.nextSyncFailure = const VaultFailure(
      code: VaultFailureCode.network,
      message: 'timeout',
    );
    await controller.syncNow();
    expect(controller.syncError, contains('raggiungibile'));
    expect(controller.sessionExpired, isFalse);

    await controller.syncNow();
    expect(controller.syncError, isNull);
  });

  test('disable sync unlinks and stops syncing', () async {
    await createUnlocked();
    await controller.enableSync(
      serverUrl: 'https://sync.example',
      email: 'a@example.com',
      password: 'master-password',
    );
    await controller.disableSync();
    expect(controller.linked, isFalse);
    await controller.save(login('A'));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(handle.syncCalls, 0);
  });
}
