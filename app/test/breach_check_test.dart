import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/breach_check.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/src/rust/api/vault.dart';
import 'package:arcanum/ui/app.dart';
import 'package:arcanum/ui/breach_check_screen.dart';

import 'fake_tools.dart';
import 'fakes.dart';

/// Known counts; 'offline' fails like a network error.
class FakeBreachApi implements BreachApi {
  FakeBreachApi(this.counts);

  final Map<String, int> counts;
  final asked = <String>[];

  @override
  Future<int> pwnedCount(String password) async {
    asked.add(password);
    if (password == 'offline') {
      throw const VaultFailure(code: VaultFailureCode.network, message: '');
    }
    return counts[password] ?? 0;
  }
}

void main() {
  late FakeBreachApi api;

  setUp(() {
    tools = FakeTools();
    api = FakeBreachApi({'123456': 37359195, 'qwerty': 3});
    breachApi = api;
  });

  tearDown(() => breachApi = const RustBreachApi());

  group('BreachChecker', () {
    test('checks each distinct password once and remembers the date', () async {
      final store = MemoryBreachPrefsStore();
      final now = DateTime(2026, 11, 8);
      final checker = BreachChecker(store: store, clock: () => now);
      await checker.checkAll(['123456', 'qwerty', '123456', '', 'safe']);

      expect(api.asked..sort(), ['123456', 'qwerty', 'safe']);
      expect(checker.countFor('123456'), 37359195);
      expect(checker.countFor('safe'), 0);
      expect(checker.hasResults, isTrue);
      expect(checker.failed, 0);
      expect(store.value.lastCheck, now);
    });

    test(
      'a failure is not "safe" and does not count as a full check',
      () async {
        final store = MemoryBreachPrefsStore();
        final checker = BreachChecker(store: store);
        await checker.checkAll(['qwerty', 'offline']);

        expect(checker.countFor('offline'), isNull);
        expect(checker.errorFor('offline'), isA<VaultFailure>());
        expect(checker.failed, 1);
        expect(store.value.lastCheck, isNull);
      },
    );

    test('clear forgets results', () async {
      final checker = BreachChecker();
      await checker.check('qwerty');
      checker.clear();
      expect(checker.countFor('qwerty'), isNull);
      expect(checker.hasResults, isFalse);
    });

    test('a lock during a check drops its late results', () async {
      final gate = Completer<int>();
      breachApi = _GatedApi(gate.future);
      final checker = BreachChecker();
      final running = checker.check('qwerty');
      expect(checker.isChecking('qwerty'), isTrue);
      checker.clear();
      gate.complete(3);
      await running;
      expect(checker.countFor('qwerty'), isNull);
      expect(checker.isChecking('qwerty'), isFalse);
    });

    test('reminder is due monthly, only when opted in', () async {
      var now = DateTime(2026, 11, 8);
      final store = MemoryBreachPrefsStore()
        ..value = BreachPrefs(lastCheck: DateTime(2026, 10, 1));
      final checker = BreachChecker(store: store, clock: () => now);
      await checker.load();
      expect(checker.checkDue, isFalse);

      await checker.setEnabled(true);
      expect(store.value.enabled, isTrue);
      expect(checker.checkDue, isTrue);
      checker.dismissReminder();
      expect(checker.checkDue, isFalse);

      await checker.checkAll(['qwerty']);
      now = now.add(const Duration(days: 29));
      expect(checker.checkDue, isFalse);
      now = now.add(const Duration(days: 1));
      expect(checker.checkDue, isTrue);
    });

    test('file store round-trips without passwords', () async {
      final dir = await Directory.systemTemp.createTemp('breach');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileBreachPrefsStore('${dir.path}/breach.json');
      expect((await store.read()).enabled, isFalse);

      final when = DateTime.fromMillisecondsSinceEpoch(1762560000000);
      await store.write(BreachPrefs(enabled: true, lastCheck: when));
      final read = await store.read();
      expect(read.enabled, isTrue);
      expect(read.lastCheck, when);
      expect(
        await File('${dir.path}/breach.json').readAsString(),
        isNot(contains('qwerty')),
      );
    });
  });

  group('UI', () {
    late VaultController controller;

    Future<void> pumpApp(
      WidgetTester tester,
      BreachChecker checker,
      List<(String, String)> items,
    ) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      controller = VaultController(
        handle: FakeVaultHandle(),
        secretKeys: MemorySecretKeyStore(),
        quickUnlock: FakeQuickUnlockStore(available: false),
      );
      await tester.runAsync(() async {
        await controller.create('master-password');
        controller.confirmEmergencyKit();
        for (final (title, password) in items) {
          await controller.save(login(title, password: password));
        }
      });
      await tester.pumpWidget(
        ArcanumApp(controller: controller, breach: checker),
      );
      await tester.pumpAndSettle();
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      controller.lock(); // stop the auto-lock timer
      controller.dispose();
    }

    testWidgets('one button checks the vault and lists compromised items', (
      tester,
    ) async {
      final checker = BreachChecker();
      await pumpApp(tester, checker, [
        ('Banca', 'qwerty'),
        ('Posta', 'unique-and-long'),
        ('Forum', '123456'),
      ]);
      expect(find.byType(MaterialBanner), findsNothing); // not opted in

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Password compromesse'));
      await tester.pumpAndSettle();
      expect(
        find.text('Il vault non è mai stato controllato per intero'),
        findsOneWidget,
      );

      await tester.tap(find.text('Controlla tutte le password'));
      await tester.pumpAndSettle();

      expect(
        find.text('2 password compaiono in violazioni di dati: cambiale'),
        findsOneWidget,
      );
      expect(find.text('Forum'), findsOneWidget);
      expect(find.text('Banca'), findsOneWidget);
      expect(find.text('Posta'), findsNothing);
      expect(
        find.text('alice · Trovata 3 volte in violazioni di dati'),
        findsOneWidget,
      );
      expect(find.textContaining('Ultimo controllo completo'), findsOneWidget);

      // Back in the list, compromised items carry a warning icon.
      Navigator.of(tester.element(find.byType(BreachCheckScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.gpp_bad_outlined), findsNWidgets(2));

      // Locking forgets the results.
      controller.lock();
      await tester.pumpAndSettle();
      expect(checker.countFor('qwerty'), isNull);
      await unmount(tester);
    });

    testWidgets('editor checks on request, without the automatic check', (
      tester,
    ) async {
      final checker = BreachChecker();
      await pumpApp(tester, checker, [('Banca', 'qwerty')]);
      await tester.tap(find.text('Banca'));
      await tester.pumpAndSettle();
      expect(api.asked, isEmpty); // nothing sent until asked

      await tester.tap(find.text('Controlla se è compromessa'));
      await tester.pumpAndSettle();
      expect(
        find.text('Trovata 3 volte in violazioni di dati'),
        findsOneWidget,
      );
      await unmount(tester);
    });

    testWidgets('automatic check runs when the editor opens', (tester) async {
      final checker = BreachChecker();
      await checker.setEnabled(true);
      await pumpApp(tester, checker, [('Posta', 'unique-and-long')]);
      expect(find.byType(MaterialBanner), findsOneWidget); // first reminder

      await tester.tap(find.text('Posta'));
      await tester.pumpAndSettle();
      expect(api.asked, ['unique-and-long']);
      expect(find.text('Non trovata nelle violazioni note'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a failed check is reported, never shown as safe', (
      tester,
    ) async {
      final checker = BreachChecker();
      await checker.setEnabled(true);
      await pumpApp(tester, checker, [('Rete', 'offline')]);
      await tester.tap(find.text('Rete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Impossibile controllare'), findsOneWidget);
      expect(find.text('Non trovata nelle violazioni note'), findsNothing);
      expect(find.text('Riprova'), findsOneWidget);
      await unmount(tester);
    });
  });
}

class _GatedApi implements BreachApi {
  _GatedApi(this.result);

  final Future<int> result;

  @override
  Future<int> pwnedCount(String password) => result;
}
