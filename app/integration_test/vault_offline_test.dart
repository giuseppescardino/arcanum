// Real native library, no server: checks the Rust core loads and works on
// the target platform (useful on iOS/Android where unit tests can't reach it).
//
//   cd app && flutter test integration_test/vault_offline_test.dart -d <device>

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:arcanum/src/rust/api/transfer.dart';
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

  testWidgets('export, import and nested groups through the native library', (
    tester,
  ) async {
    final v = await VaultHandle.open(path: '${tmp.path}/transfer.db');
    await v.create(password: utf8.encode('correct horse battery staple'));
    ItemFields item(String title, String group) => ItemFields(
      kind: VaultItemKind.login,
      title: title,
      username: 'alice',
      password: 'p,"w',
      urls: const ['https://example.com'],
      notes: 'line1\nline2',
      favorite: true,
      group: group,
    );
    // Generated classes compare list fields by identity: compare by value.
    String describe(ItemFields f) => [
      f.kind.name,
      f.title,
      f.username,
      f.password,
      f.urls.join(' '),
      f.notes,
      '${f.totp}',
      '${f.favorite}',
      f.group,
    ].join('|');
    expect(
      await v.addItems(
        items: [item('Slack', ' Lavoro / Chat '), item('Jira', 'Lavoro')],
      ),
      2,
    );
    final stored = [for (final i in await v.listItems()) i.fields];
    // Sorted by title; group paths are normalized on the way in.
    expect(stored.map((f) => f.group), ['Lavoro', 'Lavoro/Chat']);

    // Renaming a group carries its subgroups along.
    expect(await v.renameGroup(from: 'Lavoro', to: 'Ufficio'), 2);
    final renamed = [for (final i in await v.listItems()) i.fields];
    expect(renamed.map((f) => f.group), ['Ufficio', 'Ufficio/Chat']);

    final csv = await exportCsv(items: renamed);
    final fromCsv = await parseImport(data: utf8.encode(csv));
    expect(fromCsv.format, ImportFormat.csv);
    expect(fromCsv.items.map(describe), renamed.map(describe));

    final backup = await exportBackup(
      items: renamed,
      password: utf8.encode('backup password'),
    );
    expect(utf8.decode(backup), isNot(contains('Slack')));
    await expectLater(
      parseImport(data: backup),
      throwsA(
        isA<VaultFailure>().having(
          (e) => e.code,
          'code',
          VaultFailureCode.backupPasswordRequired,
        ),
      ),
    );
    await expectLater(
      parseImport(data: backup, password: utf8.encode('wrong')),
      throwsA(
        isA<VaultFailure>().having(
          (e) => e.code,
          'code',
          VaultFailureCode.wrongCredentials,
        ),
      ),
    );
    final fromBackup = await parseImport(
      data: backup,
      password: utf8.encode('backup password'),
    );
    expect(fromBackup.format, ImportFormat.arcanumBackup);
    expect(fromBackup.items.map(describe), renamed.map(describe));

    await expectLater(
      parseImport(data: utf8.encode('hello')),
      throwsA(
        isA<VaultFailure>().having(
          (e) => e.code,
          'code',
          VaultFailureCode.unsupportedFormat,
        ),
      ),
    );
  });
}
