import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/autofill/autofill_app.dart';
import 'package:arcanum/autofill/autofill_bridge.dart';
import 'package:arcanum/autofill/matching.dart';
import 'package:arcanum/src/rust/api/vault.dart';

import 'fake_tools.dart';
import 'fakes.dart';

class FakeBridge implements AutofillBridge {
  String? filledUser;
  String? filledPassword;
  bool cancelled = false;

  @override
  Future<AutofillRequest> request() async =>
      const AutofillRequest(packageName: 'x');

  @override
  Future<void> fill({
    required String username,
    required String password,
  }) async {
    filledUser = username;
    filledPassword = password;
  }

  @override
  Future<void> cancel() async => cancelled = true;
}

VaultItem item(String title, {List<String> urls = const []}) => VaultItem(
  id: title,
  updatedAt: 0,
  fields: ItemFields(
    kind: VaultItemKind.login,
    title: title,
    username: 'alice',
    password: 'pw-$title',
    urls: urls,
    notes: '',
    favorite: false,
    group: '',
  ),
);

void main() {
  group('matching', () {
    test('hosts match on label boundaries only', () {
      expect(hostsMatch('example.com', 'example.com'), isTrue);
      expect(hostsMatch('example.com', 'accounts.example.com'), isTrue);
      expect(hostsMatch('www.example.com', 'example.com'), isTrue);
      expect(hostsMatch('example.com', 'evil-example.com'), isFalse);
      expect(hostsMatch('example.com', 'example.com.evil.io'), isFalse);
    });

    test('web requests match saved URLs', () {
      const req = AutofillRequest(
        packageName: 'com.android.chrome',
        webDomain: 'login.github.com',
      );
      expect(
        isSuggested(item('GH', urls: ['https://github.com']), req),
        isTrue,
      );
      expect(isSuggested(item('GH', urls: ['github.com/login']), req), isTrue);
      expect(isSuggested(item('Other', urls: ['gitlab.com']), req), isFalse);
      // A title alone is not enough for a website.
      expect(isSuggested(item('github'), req), isFalse);
    });

    test('apps match meaningful package parts', () {
      const req = AutofillRequest(packageName: 'com.spotify.music');
      expect(isSuggested(item('Spotify'), req), isTrue);
      expect(
        isSuggested(item('x', urls: ['https://open.spotify.com']), req),
        isTrue,
      );
      expect(isSuggested(item('Bank'), req), isFalse);
      const generic = AutofillRequest(packageName: 'com.android.app');
      expect(isSuggested(item('Android stuff'), generic), isFalse);
    });

    test('secure notes are never suggested', () {
      const req = AutofillRequest(packageName: 'com.spotify.music');
      final note = VaultItem(
        id: 'n',
        updatedAt: 0,
        fields: const ItemFields(
          kind: VaultItemKind.secureNote,
          title: 'Spotify',
          username: '',
          password: '',
          urls: [],
          notes: 'x',
          favorite: false,
          group: '',
        ),
      );
      expect(isSuggested(note, req), isFalse);
    });
  });

  group('picker', () {
    late VaultController controller;
    late FakeBridge bridge;

    setUp(() async {
      tools = FakeTools();
      bridge = FakeBridge();
      controller = VaultController(
        handle: FakeVaultHandle(),
        secretKeys: MemorySecretKeyStore(),
        quickUnlock: FakeQuickUnlockStore(available: false),
      );
      await controller.create('master-password');
      controller.confirmEmergencyKit();
      await controller.save(
        ItemFields(
          kind: VaultItemKind.login,
          title: 'GitHub',
          username: 'alice',
          password: 'gh-pw',
          urls: const ['https://github.com'],
          notes: '',
          favorite: false,
          group: '',
        ),
      );
      await controller.save(
        const ItemFields(
          kind: VaultItemKind.login,
          title: 'Bank',
          username: 'bob',
          password: 'bank-pw',
          urls: ['https://bank.example'],
          notes: '',
          favorite: false,
          group: '',
        ),
      );
    });

    Future<void> pump(WidgetTester tester, AutofillRequest request) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AutofillApp(controller: controller, bridge: bridge, request: request),
      );
      await tester.pumpAndSettle();
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      controller.lock();
    }

    testWidgets('suggested item fills directly', (tester) async {
      await pump(
        tester,
        const AutofillRequest(
          packageName: 'com.android.chrome',
          webDomain: 'github.com',
        ),
      );
      expect(find.text('Richiesto da: github.com'), findsOneWidget);
      expect(find.text('Suggeriti'), findsOneWidget);

      await tester.tap(find.text('GitHub'));
      await tester.pumpAndSettle();
      expect(bridge.filledUser, 'alice');
      expect(bridge.filledPassword, 'gh-pw');
      await finish(tester);
    });

    testWidgets('non-matching site asks for confirmation', (tester) async {
      await pump(
        tester,
        const AutofillRequest(
          packageName: 'com.android.chrome',
          webDomain: 'github.com.evil.io',
        ),
      );
      expect(find.text('Suggeriti'), findsNothing);

      await tester.tap(find.text('Bank'));
      await tester.pumpAndSettle();
      expect(find.text('Sito diverso'), findsOneWidget);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(bridge.filledPassword, isNull);

      await tester.tap(find.text('Bank'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compila'));
      await tester.pumpAndSettle();
      expect(bridge.filledPassword, 'bank-pw');
      await finish(tester);
    });

    testWidgets('locked vault shows unlock first', (tester) async {
      controller.lock();
      await pump(tester, const AutofillRequest(packageName: 'com.x.app'));
      expect(find.text('Sblocca il vault'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).first,
        'master-password',
      );
      await tester.tap(find.text('Sblocca'));
      await tester.pumpAndSettle();
      expect(find.text('Scegli le credenziali'), findsOneWidget);

      await tester.tap(find.byTooltip('Annulla'));
      expect(bridge.cancelled, isTrue);
      await finish(tester);
    });
  });
}
