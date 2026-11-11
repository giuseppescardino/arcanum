import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/browser/bridge_clients.dart';
import 'package:arcanum/browser/bridge_handler.dart';
import 'package:arcanum/browser/bridge_server.dart';
import 'package:arcanum/ui/app.dart';

import 'fake_tools.dart';
import 'fakes.dart';

void main() {
  late VaultController controller;
  late MemoryBridgeClientStore store;
  late BridgeServer server;

  setUpAll(() => HttpOverrides.global = null);

  Future<void> setUpApp(WidgetTester tester) async {
    controller = VaultController(
      handle: FakeVaultHandle(),
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: FakeQuickUnlockStore(available: false),
    );
    store = MemoryBridgeClientStore()
      ..saved = [
        PairedBrowser(
          id: 'b1',
          name: 'Opera',
          key: Uint8List(32),
          created: DateTime(2026, 11, 1),
        ),
      ];
    server = BridgeServer(
      handler: BridgeHandler(
        controller: controller,
        tools: FakeTools(),
        showApp: () async {},
      ),
      crypto: FakeBridgeCrypto(),
      store: store,
      ports: const [0],
    );
    await tester.runAsync(() async {
      await controller.create('master-password');
      controller.confirmEmergencyKit();
      await server.start();
    });
    await tester.pumpWidget(ArcanumApp(controller: controller, bridge: server));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browser collegati'));
    await tester.pumpAndSettle();
  }

  // Disposing inside the test body cancels the auto-lock timer before the
  // binding checks for pending timers.
  Future<void> finish(WidgetTester tester) async {
    await tester.runAsync(server.stop);
    controller.dispose();
  }

  Future<void> pairStart(WidgetTester tester) => tester.runAsync(() async {
    final client = HttpClient();
    final req = await client.post('127.0.0.1', server.port!, '/v1');
    req.write(
      jsonEncode({
        'type': 'pair_start',
        'name': 'Chrome',
        'pub': base64.encode(List.filled(32, 3)),
      }),
    );
    await (await req.close()).drain<void>();
    client.close();
  });

  testWidgets('menu entry opens the browsers screen with the list', (
    tester,
  ) async {
    await setUpApp(tester);
    expect(find.text('Collega browser'), findsOneWidget);
    expect(find.text('Opera'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('a pending pairing shows the code and can be approved', (
    tester,
  ) async {
    await setUpApp(tester);
    await tester.tap(find.text('Collega browser'));
    // The waiting spinner never settles: pump frames instead.
    await tester.pump();
    await pairStart(tester);
    await tester.pumpAndSettle();

    expect(find.text('Collegare Chrome?'), findsOneWidget);
    expect(find.text('123 456'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Collega'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('Collegare Chrome?'), findsNothing);
    expect(find.text('Chrome'), findsOneWidget);
    expect(store.saved.map((b) => b.name), ['Opera', 'Chrome']);

    await finish(tester);
  });

  testWidgets('a pending pairing can be rejected', (tester) async {
    await setUpApp(tester);
    await tester.tap(find.text('Collega browser'));
    // The waiting spinner never settles: pump frames instead.
    await tester.pump();
    await pairStart(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rifiuta'));
    await tester.pumpAndSettle();
    expect(find.text('Collegare Chrome?'), findsNothing);
    expect(store.saved.single.name, 'Opera');

    await finish(tester);
  });

  testWidgets('revoke removes the browser', (tester) async {
    await setUpApp(tester);
    await tester.tap(find.text('Revoca'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Opera'), findsNothing);
    expect(store.saved, isEmpty);

    await finish(tester);
  });

  testWidgets('no menu entry without a bridge', (tester) async {
    controller = VaultController(
      handle: FakeVaultHandle(),
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: FakeQuickUnlockStore(available: false),
    );
    await tester.runAsync(() async {
      await controller.create('master-password');
      controller.confirmEmergencyKit();
    });
    await tester.pumpWidget(ArcanumApp(controller: controller));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Browser collegati'), findsNothing);
    controller.dispose();
  });
}
