// Real native library + a running sync server.
//
//   cd server && DATABASE_URL=postgres://postgres@localhost:5433/arcanum_dev \
//     BIND_ADDR=127.0.0.1:8080 cargo run
//   cd app && flutter test integration_test -d windows
//
// Override the server with --dart-define=ARCANUM_TEST_SERVER=http://...

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:arcanum/src/rust/api/vault.dart';
import 'package:arcanum/src/rust/frb_generated.dart';

const server = String.fromEnvironment(
  'ARCANUM_TEST_SERVER',
  defaultValue: 'http://127.0.0.1:8080',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUpAll(() async {
    await RustLib.init();
    tmp = await Directory.systemTemp.createTemp('arcanum_it_');
  });

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // Best effort: Windows may still hold the SQLite WAL files briefly.
    }
  });

  ItemFields login(String title, String password) => ItemFields(
    kind: VaultItemKind.login,
    title: title,
    username: 'alice',
    password: password,
    urls: const ['https://example.com'],
    notes: '',
    favorite: false,
    group: '',
  );

  testWidgets('two devices sync through the server', (tester) async {
    final pw = utf8.encode('correct horse battery staple');

    // Device A: create, add an item, enable sync.
    final a = await VaultHandle.open(path: '${tmp.path}/a.db');
    final sk = await a.create(password: pw);
    await a.addItem(fields: login('GitHub', 'gh-1'));
    final reg = await a.registerSync(
      serverUrl: server,
      password: pw,
      secretKey: sk,
      deviceName: 'IT device A',
      invite: const String.fromEnvironment('ARCANUM_INVITE'),
    );
    expect(reg.pushed, 1);
    expect(await a.isLinked(), isTrue);

    // Device B: sign in from scratch.
    final b = await VaultHandle.open(path: '${tmp.path}/b.db');
    final signIn = await b.signIn(
      serverUrl: server,
      password: pw,
      secretKey: sk,
      deviceName: 'IT device B',
    );
    expect(signIn.pulled, 1);
    final items = await b.listItems();
    expect(items.single.fields.password, 'gh-1');

    // Edit on B, sync back to A.
    await b.updateItem(id: items.single.id, fields: login('GitHub', 'gh-2'));
    expect((await b.syncNow()).pushed, 1);
    expect((await a.syncNow()).pulled, 1);
    expect((await a.listItems()).single.fields.password, 'gh-2');

    // Wrong password on a third device is rejected with a typed error.
    final c = await VaultHandle.open(path: '${tmp.path}/c.db');
    await expectLater(
      c.signIn(
        serverUrl: server,
          password: utf8.encode('wrong'),
        secretKey: sk,
        deviceName: 'IT device C',
      ),
      throwsA(
        isA<VaultFailure>().having(
          (f) => f.code,
          'code',
          VaultFailureCode.invalidLogin,
        ),
      ),
    );

    // Plain HTTP to a non-local host is refused before any request.
    final d = await VaultHandle.open(path: '${tmp.path}/d.db');
    await expectLater(
      d.signIn(
        serverUrl: 'http://localhost@example.com',
          password: pw,
        secretKey: sk,
        deviceName: 'IT device D',
      ),
      throwsA(
        isA<VaultFailure>().having(
          (f) => f.code,
          'code',
          VaultFailureCode.invalidServerUrl,
        ),
      ),
    );

    await a.unlinkSync();
    expect(await a.isLinked(), isFalse);

    // Release the native handles so the SQLite files can be deleted.
    for (final h in [a, b, c, d]) {
      h.dispose();
    }
  });
}
