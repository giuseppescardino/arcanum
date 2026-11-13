import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/file_dialogs.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/transfer.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/ui/app.dart';

import 'fake_tools.dart';
import 'fakes.dart';
import 'window.dart';

void main() {
  late VaultController controller;
  late FakeFileDialogs dialogs;

  setUp(() async {
    tools = FakeTools();
    transfer = FakeTransfer();
    fileDialogs = dialogs = FakeFileDialogs();
    controller = VaultController(
      handle: FakeVaultHandle(),
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: FakeQuickUnlockStore(available: false),
    );
    await controller.create('master-password');
    controller.confirmEmergencyKit();
  });

  tearDown(() => controller.dispose());

  Future<void> openMenu(WidgetTester tester, String entry) async {
    useNarrowWindow(tester);
    await tester.pumpWidget(ArcanumApp(controller: controller));
    // Group headers have a menu of their own: take the app bar's.
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(entry));
    await tester.pumpAndSettle();
  }

  /// Runs [body], then unmounts and locks so no timer outlives the test.
  void appTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      controller.lock();
    });
  }

  test('import skips what the vault already has and repeats', () async {
    await controller.save(login('Jira', password: 'a'));
    final incoming = [
      login('Jira', password: 'a'),
      login('Jira', password: 'changed'),
      login('Slack', password: 'b'),
      login('Slack', password: 'b'),
    ];
    final fresh = controller.newItemsAmong(incoming);
    expect(fresh.map((f) => '${f.title}:${f.password}'), [
      'Jira:changed',
      'Slack:b',
    ]);

    expect(await controller.importItems(fresh), 2);
    expect(controller.items, hasLength(3));
    expect(controller.newItemsAmong(incoming), isEmpty);
  });

  test(
    'the vault stays unlocked on pause only while a dialog is open',
    () async {
      expect(controller.locksOnPause, isTrue);
      await controller.keepUnlocked(() async {
        expect(controller.locksOnPause, isFalse);
      });
      expect(controller.locksOnPause, isTrue);
      // Also released when the dialog fails.
      await expectLater(
        controller.keepUnlocked<void>(() async => throw StateError('x')),
        throwsStateError,
      );
      expect(controller.locksOnPause, isTrue);
    },
  );

  appTest('importing a CSV previews it and adds the new items', (tester) async {
    await controller.save(login('Jira', password: 'a'));
    dialogs.toPick = utf8.encode('Jira|a|\nSlack|b|Lavoro/Chat');
    await openMenu(tester, 'Importa…');

    expect(find.text('Formato riconosciuto: CSV'), findsOneWidget);
    expect(find.text('1 elemento da importare'), findsOneWidget);
    expect(find.text('1 è già nel vault e verrà saltato'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Importa'));
    await tester.pumpAndSettle();

    expect(controller.items.map((i) => i.fields.title), ['Jira', 'Slack']);
    expect(controller.groups, ['Lavoro', 'Lavoro/Chat']);
    expect(find.text('1 elemento importato'), findsOneWidget);
  });

  appTest('cancelling the file dialog imports nothing', (tester) async {
    await openMenu(tester, 'Importa…');
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.items, isEmpty);
  });

  appTest('an unknown file is refused', (tester) async {
    dialogs.toPick = utf8.encode('not a credential export');
    await openMenu(tester, 'Importa…');
    expect(
      find.text('Il file non è in un formato che Arcanum sa importare.'),
      findsOneWidget,
    );
    expect(controller.items, isEmpty);
  });

  appTest('an encrypted backup asks for its password', (tester) async {
    dialogs.toPick = utf8.encode('BACKUP:backup-password\nSlack|b|');
    await openMenu(tester, 'Importa…');

    expect(find.text('Password del backup'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Apri'));
    await tester.pumpAndSettle();
    expect(find.text('Password del backup errata'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'backup-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Apri'));
    await tester.pumpAndSettle();
    expect(find.text('Formato riconosciuto: Backup Arcanum'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Importa'));
    await tester.pumpAndSettle();
    expect(controller.items.single.fields.title, 'Slack');
  });

  appTest('export writes an encrypted backup by default', (tester) async {
    await controller.save(login('Jira', password: 'a', group: 'Lavoro'));
    await openMenu(tester, 'Esporta…');

    // The backup password must be long enough and typed twice.
    await tester.tap(find.widgetWithText(FilledButton, 'Esporta'));
    await tester.pumpAndSettle();
    expect(find.text('Almeno 10 caratteri'), findsOneWidget);
    expect(dialogs.savedBytes, isNull);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'backup-password');
    await tester.enterText(fields.at(1), 'backup-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Esporta'));
    await tester.pumpAndSettle();

    expect(
      dialogs.savedName,
      matches(r'^arcanum-backup-\d{4}-\d\d-\d\d\.json$'),
    );
    expect(
      utf8.decode(dialogs.savedBytes!),
      'BACKUP:backup-password\nJira|a|Lavoro',
    );
    expect(find.text('1 elemento esportato'), findsOneWidget);
  });

  appTest('CSV export warns that the file is not encrypted', (tester) async {
    await controller.save(login('Jira', password: 'a'));
    await openMenu(tester, 'Esporta…');

    await tester.tap(find.text('CSV in chiaro'));
    await tester.pumpAndSettle();
    expect(find.textContaining('non è cifrato'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);

    // Cancelling the save dialog keeps the export dialog open.
    dialogs.cancelSave = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Esporta'));
    await tester.pumpAndSettle();
    expect(dialogs.savedBytes, isNull);
    expect(find.text('Esporta elementi'), findsOneWidget);

    dialogs.cancelSave = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Esporta'));
    await tester.pumpAndSettle();
    expect(dialogs.savedName, endsWith('.csv'));
    expect(utf8.decode(dialogs.savedBytes!), 'Jira|a|');
  });
}
