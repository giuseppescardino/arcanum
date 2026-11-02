import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/ui/app.dart';

import 'fake_tools.dart';
import 'fakes.dart';

void main() {
  setUp(() => tools = FakeTools());

  Future<VaultController> unlockedWith(List<(String, String)> items) async {
    final controller = VaultController(
      handle: FakeVaultHandle(),
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: FakeQuickUnlockStore(available: false),
    );
    await controller.create('master-password');
    controller.confirmEmergencyKit();
    for (final (title, group) in items) {
      await controller.save(login(title, group: group));
    }
    return controller;
  }

  test('groups are unique, sorted and renamable', () async {
    final c = await unlockedWith([
      ('Jira', 'lavoro'),
      ('Netflix', 'Svago'),
      ('Slack', 'lavoro'),
      ('Bank', ''),
    ]);
    expect(c.groups, ['lavoro', 'Svago']);

    await c.renameGroup('lavoro', 'Ufficio');
    expect(c.groups, ['Svago', 'Ufficio']);

    await c.renameGroup('Svago', '');
    expect(c.groups, ['Ufficio']);
    expect(
      c.items.where((i) => i.fields.group.isEmpty).map((i) => i.fields.title),
      ['Bank', 'Netflix'],
    );
    c.dispose();
  });

  testWidgets('list is split by group, collapsible and filterable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await unlockedWith([
      ('Jira', 'Lavoro'),
      ('Netflix', 'Svago'),
      ('Bank', ''),
    ]);
    await tester.pumpWidget(ArcanumApp(controller: c));

    // Section headers ('Senza gruppo' also appears as a filter chip).
    expect(find.widgetWithText(ListTile, 'Lavoro'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Senza gruppo'), findsOneWidget);
    expect(find.text('Jira'), findsOneWidget);

    // Collapse a section.
    await tester.tap(find.widgetWithText(ListTile, 'Lavoro'));
    await tester.pump();
    expect(find.text('Jira'), findsNothing);
    expect(find.text('Netflix'), findsOneWidget);

    // Filter by a group: only its items, no headers.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Svago'));
    await tester.pump();
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('Bank'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Svago'), findsNothing);

    // A new item starts in the group being browsed.
    await tester.tap(find.text('Nuovo'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Svago'), findsOneWidget);

    c.dispose();
  });

  testWidgets('deleting a group keeps its items', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await unlockedWith([('Jira', 'Lavoro'), ('Bank', '')]);
    await tester.pumpWidget(ArcanumApp(controller: c));

    await tester.tap(find.byTooltip('Azioni gruppo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina gruppo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Elimina gruppo'));
    await tester.pumpAndSettle();

    expect(c.groups, isEmpty);
    expect(find.text('Jira'), findsOneWidget);
    // No groups left: plain list, no chips or headers.
    expect(find.byType(ChoiceChip), findsNothing);
    c.dispose();
  });
}
