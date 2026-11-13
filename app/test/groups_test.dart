import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/groups.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/src/rust/api/vault.dart';
import 'package:arcanum/ui/app.dart';
import 'package:arcanum/ui/vault_list.dart';

import 'fake_tools.dart';
import 'fakes.dart';
import 'window.dart';

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

  void desktop(WidgetTester tester) {
    useNarrowWindow(tester);
  }

  Finder header(String name) => find.widgetWithText(ListTile, name);
  Finder chip(String name) => find.widgetWithText(ChoiceChip, name);

  test('group paths are normalized and ordered as a tree', () {
    expect(normalizeGroup(' Lavoro / Clienti //Acme/ '), 'Lavoro/Clienti/Acme');
    expect(groupRoot('Lavoro/Clienti'), 'Lavoro');
    expect(groupLeaf('Lavoro/Clienti'), 'Clienti');
    expect(groupDepth('Lavoro/Clienti/Acme'), 2);
    expect(groupContains('Lavoro', 'Lavoro/Clienti'), isTrue);
    expect(groupContains('Lavoro', 'Lavoro'), isTrue);
    // Per level, not per character.
    expect(groupContains('Lavoro', 'Lavorone'), isFalse);
    expect(groupAncestors('A/B/C'), ['A', 'A/B']);
    // Parents are implied; subgroups follow their parent.
    expect(groupTree(['svago', 'Lavoro/Clienti/Acme', 'Banche', '']), [
      'Banche',
      'Lavoro',
      'Lavoro/Clienti',
      'Lavoro/Clienti/Acme',
      'svago',
    ]);
  });

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

  test('renaming a group moves its subgroups', () async {
    final c = await unlockedWith([
      ('Slack', 'Lavoro'),
      ('Jira', 'Lavoro/Clienti/Acme'),
      ('Netflix', 'Svago'),
    ]);
    expect(c.groups, [
      'Lavoro',
      'Lavoro/Clienti',
      'Lavoro/Clienti/Acme',
      'Svago',
    ]);
    expect(c.rootGroups, ['Lavoro', 'Svago']);

    await c.renameGroup('Lavoro', 'Ufficio');
    expect(c.groups, [
      'Svago',
      'Ufficio',
      'Ufficio/Clienti',
      'Ufficio/Clienti/Acme',
    ]);

    // Deleting a group ungroups its whole subtree.
    await c.renameGroup('Ufficio/Clienti', '');
    expect(c.groups, ['Svago', 'Ufficio']);
    c.dispose();
  });

  testWidgets('several groups start collapsed and open on tap', (tester) async {
    desktop(tester);
    final c = await unlockedWith([
      ('Jira', 'Lavoro'),
      ('Netflix', 'Svago'),
      ('Bank', ''),
    ]);
    await tester.pumpWidget(ArcanumApp(controller: c));

    // Section headers ('Senza gruppo' also appears as a filter chip).
    expect(header('Lavoro'), findsOneWidget);
    expect(header('Senza gruppo'), findsOneWidget);
    // Every section is closed: no item shows.
    expect(find.text('Jira'), findsNothing);
    expect(find.text('Netflix'), findsNothing);
    expect(find.text('Bank'), findsNothing);

    // Open one section, then close it again.
    await tester.tap(header('Lavoro'));
    await tester.pump();
    expect(find.text('Jira'), findsOneWidget);
    expect(find.text('Netflix'), findsNothing);
    await tester.tap(header('Lavoro'));
    await tester.pump();
    expect(find.text('Jira'), findsNothing);

    // A search shows its matches whatever is collapsed.
    await tester.enterText(find.byType(TextField), 'netf');
    await tester.pump();
    expect(find.text('Netflix'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('Netflix'), findsNothing);

    // Filter by a group: only its items, no headers.
    await tester.tap(chip('Svago'));
    await tester.pump();
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('Bank'), findsNothing);
    expect(header('Svago'), findsNothing);

    // A new item starts in the group being browsed.
    await tester.tap(find.text('Nuovo'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Svago'), findsOneWidget);

    c.dispose();
  });

  testWidgets('a single group stays open', (tester) async {
    desktop(tester);
    final c = await unlockedWith([('Jira', 'Lavoro'), ('Bank', '')]);
    await tester.pumpWidget(ArcanumApp(controller: c));

    expect(header('Lavoro'), findsOneWidget);
    expect(find.text('Jira'), findsOneWidget);
    expect(find.text('Bank'), findsOneWidget);

    await tester.tap(header('Lavoro'));
    await tester.pump();
    expect(find.text('Jira'), findsNothing);
    expect(find.text('Bank'), findsOneWidget);
    c.dispose();
  });

  testWidgets('subgroups nest in the list; the bar shows only root groups', (
    tester,
  ) async {
    desktop(tester);
    final c = await unlockedWith([
      ('Slack', 'Lavoro'),
      ('Jira', 'Lavoro/Clienti/Acme'),
      ('Netflix', 'Svago'),
    ]);
    await tester.pumpWidget(ArcanumApp(controller: c));

    // Chips: "all" plus one per root group.
    expect(find.byType(ChoiceChip), findsNWidgets(3));
    expect(chip('Lavoro'), findsOneWidget);
    expect(chip('Svago'), findsOneWidget);
    expect(chip('Clienti'), findsNothing);
    expect(find.textContaining('/'), findsNothing);

    // Closed root: its subgroups are hidden with it. The count covers
    // the whole subtree.
    expect(header('Clienti'), findsNothing);
    expect(
      find.descendant(of: header('Lavoro'), matching: find.text('2')),
      findsOneWidget,
    );

    // Open level by level.
    await tester.tap(header('Lavoro'));
    await tester.pump();
    expect(find.text('Slack'), findsOneWidget);
    expect(header('Clienti'), findsOneWidget);
    expect(header('Acme'), findsNothing);
    expect(find.text('Jira'), findsNothing);

    await tester.tap(header('Clienti'));
    await tester.pump();
    await tester.tap(header('Acme'));
    await tester.pump();
    expect(find.text('Jira'), findsOneWidget);

    // Closing the root hides everything below it again.
    await tester.tap(header('Lavoro'));
    await tester.pump();
    expect(find.text('Jira'), findsNothing);
    expect(header('Acme'), findsNothing);

    // Filtering by the root shows its items and its subgroups' headers,
    // not its own.
    await tester.tap(chip('Lavoro'));
    await tester.pump();
    expect(header('Lavoro'), findsNothing);
    expect(find.text('Slack'), findsOneWidget);
    expect(header('Clienti'), findsOneWidget);
    expect(find.text('Netflix'), findsNothing);

    c.dispose();
  });

  testWidgets('deleting a group keeps its items', (tester) async {
    desktop(tester);
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

  test('group colors are kept apart from items and inherited', () async {
    final c = await unlockedWith([('Jira', 'Lavoro/Clienti'), ('Bank', '')]);
    await c.setGroupColor('Lavoro', 0xFF1E88E5);
    expect(c.items.map((i) => i.fields.title), ['Bank', 'Jira']);
    expect(c.groups, ['Lavoro', 'Lavoro/Clienti']);
    expect(c.groupColors, {'Lavoro': 0xFF1E88E5});
    // A subgroup without its own color uses its parent's.
    expect(c.colorOfGroup('Lavoro/Clienti'), 0xFF1E88E5);
    expect(c.colorOfGroup(''), isNull);

    await c.setGroupColor('Lavoro/Clienti', 0xFFE53935);
    expect(c.colorOfGroup('Lavoro/Clienti'), 0xFFE53935);

    // The color follows a rename and goes away with the group.
    await c.renameGroup('Lavoro', 'Ufficio');
    expect(c.colorOfGroup('Ufficio'), 0xFF1E88E5);
    await c.renameGroup('Ufficio', '');
    expect(c.groupColors, isEmpty);

    c.dispose();
  });

  testWidgets('a group gets a color from its menu', (tester) async {
    desktop(tester);
    final c = await unlockedWith([('Jira', 'Lavoro'), ('Netflix', 'Svago')]);
    await tester.pumpWidget(ArcanumApp(controller: c));

    await tester.tap(
      find.descendant(
        of: header('Lavoro'),
        matching: find.byTooltip('Azioni gruppo'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Colore'));
    await tester.pumpAndSettle();
    expect(find.text('Colore di "Lavoro"'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('#1e88e5'));
    await tester.pumpAndSettle();

    expect(c.groupColors, {'Lavoro': 0xFF1E88E5});
    final icon = tester.widget<Icon>(
      find.descendant(
        of: header('Lavoro'),
        matching: find.byIcon(Icons.folder_outlined),
      ),
    );
    expect(icon.color, const Color(0xFF1E88E5));

    c.dispose();
  });

  test('filterItems applies filter and query together', () async {
    final c = await unlockedWith([]);
    await c.save(login('A', group: 'Work', favorite: true));
    await c.save(login('B', group: 'Work/Clients'));
    await c.save(login('C', expiresOn: '2020-01-01'));
    final now = DateTime(2026, 11, 13);
    List<String> titles(List<VaultItem> items) => [
      for (final i in items) i.fields.title,
    ];

    expect(titles(filterItems(c, const AllItems(), '', now)), ['A', 'B', 'C']);
    expect(titles(filterItems(c, const GroupItems('Work'), '', now)), [
      'A',
      'B',
    ]);
    expect(titles(filterItems(c, const GroupItems(''), '', now)), ['C']);
    expect(titles(filterItems(c, const FavoriteItems(), '', now)), ['A']);
    expect(titles(filterItems(c, const ExpiringItems(), '', now)), ['C']);
    expect(titles(filterItems(c, const GroupItems('Work'), 'b', now)), ['B']);
    expect(const GroupItems('Work'), const GroupItems('Work'));
    expect(const AllItems(), isNot(const FavoriteItems()));
    c.dispose();
  });
}
