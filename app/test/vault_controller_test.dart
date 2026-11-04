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
    );
  });

  tearDown(() => controller.dispose());

  test('new install starts in setup', () async {
    await controller.init();
    expect(controller.stage, VaultStage.setup);
  });

  test('create stores the secret key and shows the emergency kit', () async {
    await controller.init();
    await controller.create('master-password');

    expect(controller.stage, VaultStage.emergencyKit);
    expect(controller.pendingSecretKey, fakeSecretKey);
    expect(keys.value, fakeSecretKey);

    controller.confirmEmergencyKit();
    expect(controller.stage, VaultStage.unlocked);
    expect(controller.pendingSecretKey, isNull);
  });

  test('signOut erases the vault and returns to setup', () async {
    await controller.create('master-password');
    controller.confirmEmergencyKit();
    await controller.save(login('GitHub'));

    await controller.signOut();
    expect(controller.stage, VaultStage.setup);
    expect(controller.items, isEmpty);
    expect(controller.hasStoredSecretKey, isFalse);
    expect(controller.linked, isFalse);
    expect(keys.value, isNull);

    // A fresh start sees an empty, uninitialized vault.
    await controller.init();
    expect(controller.stage, VaultStage.setup);
  });

  test('lock clears decrypted items; unlock uses stored key', () async {
    await controller.create('master-password');
    controller.confirmEmergencyKit();
    await controller.save(login('GitHub'));
    expect(controller.items, hasLength(1));

    controller.lock();
    expect(controller.stage, VaultStage.locked);
    expect(controller.items, isEmpty);
    expect(handle.unlocked, isFalse);

    await controller.unlock('master-password');
    expect(controller.stage, VaultStage.unlocked);
    expect(controller.items.single.fields.title, 'GitHub');
  });

  test('wrong password keeps the vault locked', () async {
    await controller.create('master-password');
    controller.confirmEmergencyKit();
    controller.lock();

    await expectLater(
      controller.unlock('nope'),
      throwsA(
        isA<VaultFailure>().having(
          (f) => f.code,
          'code',
          VaultFailureCode.wrongCredentials,
        ),
      ),
    );
    expect(controller.stage, VaultStage.locked);
  });

  test('forgotten secret key must be typed again', () async {
    await controller.create('master-password');
    controller.confirmEmergencyKit();
    await controller.forgetSecretKey();
    controller.lock();

    expect(controller.hasStoredSecretKey, isFalse);
    await expectLater(controller.unlock('master-password'), throwsStateError);

    await controller.unlock('master-password', secretKey: fakeSecretKey);
    expect(controller.stage, VaultStage.unlocked);
    expect(keys.value, fakeSecretKey);
  });

  test('auto-lock after inactivity', () async {
    final c = VaultController(
      handle: handle,
      secretKeys: keys,
      quickUnlock: FakeQuickUnlockStore(available: false),
      autoLockAfter: const Duration(milliseconds: 50),
    );
    await c.create('master-password');
    c.confirmEmergencyKit();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(c.stage, VaultStage.locked);
    c.dispose();
  });

  test('update and delete reload the list', () async {
    await controller.create('master-password');
    controller.confirmEmergencyKit();
    await controller.save(login('A'));
    final id = controller.items.single.id;

    await controller.save(login('A2'), id: id);
    expect(controller.items.single.fields.title, 'A2');

    await controller.delete(id);
    expect(controller.items, isEmpty);
  });
}
