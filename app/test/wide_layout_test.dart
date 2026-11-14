import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/src/rust/api/vault.dart';
import 'package:arcanum/ui/app.dart';
import 'package:arcanum/ui/vault_list.dart';
import 'package:arcanum/ui/vault_sidebar.dart';

import 'fake_tools.dart';
import 'fakes.dart';
import 'window.dart';

const _hint = 'Seleziona una voce per vederne i dettagli.';

void main() {
  setUp(() => tools = FakeTools());

  late VaultController controller;

  /// 'Bank' (Work), 'Mail' (Personale, favorite) and, unless
  /// [withExpired] is false, 'Old' (no group, expired).
  Future<void> pumpApp(WidgetTester tester, {bool withExpired = true}) async {
    controller = VaultController(
      handle: FakeVaultHandle(),
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: FakeQuickUnlockStore(available: false),
    );
    await controller.create('master-password');
    controller.confirmEmergencyKit();
    final items = <ItemFields>[
      login('Bank', group: 'Work'),
      login('Mail', group: 'Personale', favorite: true),
      if (withExpired) login('Old', expiresOn: '2020-01-01'),
    ];
    for (final f in items) {
      await controller.save(f);
    }
    await tester.pumpWidget(ArcanumApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.lock();
    controller.dispose();
  }

  /// With several groups the list opens with its sections closed.
  Future<void> openListSection(WidgetTester tester, String group) async {
    await tester.tap(
      find.descendant(of: find.byType(VaultList), matching: find.text(group)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('wide: sidebar, list and item view side by side', (tester) async {
    useWideWindow(tester);
    await pumpApp(tester);
    expect(find.text('Preferiti'), findsOneWidget);
    expect(find.text('Gruppi'), findsOneWidget);
    expect(find.text('Password compromesse'), findsOneWidget);
    expect(find.text('Impostazioni'), findsOneWidget);
    expect(find.text(_hint), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);

    await openListSection(tester, 'Work');
    await openListSection(tester, 'Personale');
    await tester.tap(find.text('Bank'));
    await tester.pumpAndSettle();
    expect(find.text('Modifica'), findsOneWidget);
    expect(find.text(_hint), findsNothing);
    expect(find.text('Mail'), findsOneWidget); // the list is still there
    await unmount(tester);
  });

  testWidgets('wide: sidebar counts', (tester) async {
    useWideWindow(tester);
    await pumpApp(tester);
    String countOf(String label) {
      final entry = tester.widget<SidebarEntry>(
        find
            .ancestor(
              of: find.descendant(
                of: find.byKey(const Key('vaultSidebar')),
                matching: find.text(label),
              ),
              matching: find.byType(SidebarEntry),
            )
            .first,
      );
      return '${entry.count}';
    }

    expect(countOf('Tutti'), '3');
    expect(countOf('Preferiti'), '1');
    expect(countOf('Scadenze'), '1');
    expect(countOf('Work'), '1');
    expect(countOf('Senza gruppo'), '1');
    await unmount(tester);
  });

  testWidgets('wide: sidebar filters', (tester) async {
    useWideWindow(tester);
    await pumpApp(tester);
    await tester.tap(find.text('Preferiti'));
    await tester.pumpAndSettle();
    expect(find.text('Mail'), findsOneWidget);
    expect(find.text('Bank'), findsNothing);

    await tester.tap(find.text('Scadenze'));
    await tester.pumpAndSettle();
    expect(find.text('Old'), findsOneWidget);
    expect(find.text('Mail'), findsNothing);

    await tester.tap(find.widgetWithText(SidebarEntry, 'Work'));
    await tester.pumpAndSettle();
    expect(find.text('Bank'), findsOneWidget);
    expect(find.text('Old'), findsNothing);
    await unmount(tester);
  });

  testWidgets('wide: Scadenze is hidden when nothing expires', (tester) async {
    useWideWindow(tester);
    await pumpApp(tester, withExpired: false);
    expect(find.text('Scadenze'), findsNothing);
    expect(find.text('Senza gruppo'), findsNothing);
    await unmount(tester);
  });

  testWidgets('wide: the selected item disappearing clears the item view', (
    tester,
  ) async {
    useWideWindow(tester);
    await pumpApp(tester);
    await openListSection(tester, 'Work');
    await tester.tap(find.text('Bank'));
    await tester.pumpAndSettle();
    expect(find.text('Modifica'), findsOneWidget);

    final id = controller.items.firstWhere((i) => i.fields.title == 'Bank').id;
    await tester.runAsync(() => controller.delete(id));
    await tester.pumpAndSettle();
    expect(find.text('Modifica'), findsNothing);
    expect(find.text(_hint), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('resizing across the breakpoint keeps search and filter', (
    tester,
  ) async {
    useWideWindow(tester);
    await pumpApp(tester);
    await tester.enterText(find.byType(TextField).first, 'ban');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank'));
    await tester.pumpAndSettle();
    expect(find.text('Modifica'), findsOneWidget);

    useNarrowWindow(tester);
    await tester.pumpAndSettle();
    expect(find.text('ban'), findsOneWidget); // search text kept
    expect(find.text('Bank'), findsOneWidget);
    expect(find.text('Mail'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(tester.takeException(), isNull);

    useWideWindow(tester);
    await tester.pumpAndSettle();
    expect(find.text('ban'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('a Preferiti filter falls back to all items on narrow', (
    tester,
  ) async {
    useWideWindow(tester);
    await pumpApp(tester);
    await tester.tap(find.text('Preferiti'));
    await tester.pumpAndSettle();

    useNarrowWindow(tester);
    await tester.pumpAndSettle();
    final all = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Tutti'),
    );
    expect(all.selected, isTrue);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('narrow: chips, FAB and a Scadenze chip only when needed', (
    tester,
  ) async {
    useNarrowWindow(tester);
    await pumpApp(tester);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Scadenze'), findsOneWidget);
    expect(find.text('Preferiti'), findsNothing);
    expect(find.text(_hint), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Scadenze'));
    await tester.pumpAndSettle();
    expect(find.text('Old'), findsOneWidget);
    expect(find.text('Bank'), findsNothing);

    // Tapping a row still opens the item full screen.
    await tester.tap(find.text('Old'));
    await tester.pumpAndSettle();
    expect(find.text('Modifica'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await unmount(tester);
  });

  testWidgets('narrow: no Scadenze chip when nothing expires', (tester) async {
    useNarrowWindow(tester);
    await pumpApp(tester, withExpired: false);
    expect(find.widgetWithText(ChoiceChip, 'Scadenze'), findsNothing);
    await unmount(tester);
  });

  testWidgets('wide: Nuovo and Modifica open the editor as a route; '
      'lock closes it', (tester) async {
    useWideWindow(tester);
    await pumpApp(tester);
    await tester.tap(find.text('Nuovo'));
    await tester.pumpAndSettle();
    expect(find.text('Salva'), findsOneWidget);
    Navigator.of(tester.element(find.text('Salva'))).pop();
    await tester.pumpAndSettle();

    await openListSection(tester, 'Work');
    await tester.tap(find.text('Bank'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifica'));
    await tester.pumpAndSettle();
    expect(find.text('Salva'), findsOneWidget);
    expect(find.byType(TextFormField), findsWidgets);

    controller.lock();
    await tester.pumpAndSettle();
    expect(find.text('Sblocca il vault'), findsOneWidget);
    expect(find.text('Salva'), findsNothing);
    await unmount(tester);
  });

  testWidgets('wide: the sidebar opens settings and the breach check', (
    tester,
  ) async {
    useWideWindow(tester);
    await pumpApp(tester);
    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();
    expect(find.text('Zona pericolosa'), findsOneWidget);
    Navigator.of(tester.element(find.text('Zona pericolosa'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Password compromesse'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Password compromesse'), findsOneWidget);
    await unmount(tester);
  });
}
