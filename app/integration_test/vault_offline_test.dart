// Real native library, no server: checks the Rust core loads and works on
// the target platform (useful on iOS/Android where unit tests can't reach it).
//
//   cd app && flutter test integration_test/vault_offline_test.dart -d <device>

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:arcanum/src/rust/api/vault.dart';
import 'package:arcanum/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUpAll(() async {
    await RustLib.init();
    tmp = await Directory.systemTemp.createTemp('arcanum_it_offline_');
  });

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // Best effort: Windows may still hold the SQLite WAL files briefly.
    }
  });

  testWidgets('create, add, reopen, unlock and regroup a local vault', (
    tester,
  ) async {
    final path = '${tmp.path}/vault.db';
    final pw = utf8.encode('correct horse battery staple');

    final v = await VaultHandle.open(path: path);
    expect(await v.isInitialized(), isFalse);
    final sk = await v.create(password: pw);
    await v.addItem(
      fields: const ItemFields(
        kind: VaultItemKind.login,
        title: 'GitHub',
        username: 'alice',
        password: 'gh-1',
        urls: ['https://github.com'],
        notes: '',
        favorite: false,
        group: 'Lavoro',
      ),
    );

    final reopened = await VaultHandle.open(path: path);
    expect(await reopened.isInitialized(), isTrue);
    await expectLater(
      reopened.unlock(password: utf8.encode('wrong'), secretKey: sk),
      throwsA(isA<VaultFailure>()),
    );
    await reopened.unlock(password: pw, secretKey: sk);
    final item = (await reopened.listItems()).single;
    expect(item.fields.password, 'gh-1');
    expect(item.fields.group, 'Lavoro');

    expect(await reopened.renameGroup(from: 'Lavoro', to: 'Ufficio'), 1);
    expect((await reopened.listItems()).single.fields.group, 'Ufficio');
  });
}
