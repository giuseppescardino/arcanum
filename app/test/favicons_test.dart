import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/favicons.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/ui/app.dart';

import 'fake_tools.dart';
import 'fakes.dart';
import 'window.dart';

/// 1x1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  setUp(() => tools = FakeTools());

  test('only public host names are asked for an icon', () {
    expect(faviconHost('https://www.example.com/login?x=1'), 'example.com');
    expect(faviconHost('accounts.example.co.uk'), 'accounts.example.co.uk');
    expect(faviconHost('https://192.168.1.10/admin'), isNull);
    expect(faviconHost('http://localhost:8080'), isNull);
    expect(faviconHost('https://intranet/'), isNull);
    expect(faviconHost(''), isNull);
  });

  test('bodies that are not images are refused', () {
    expect(looksLikeImage(_png), isTrue);
    expect(looksLikeImage([0, 0, 1, 0, 1, 0]), isTrue);
    expect(looksLikeImage(utf8.encode('<!doctype html>')), isFalse);
    expect(looksLikeImage(utf8.encode('<svg xmlns="x"/>')), isFalse);
    expect(looksLikeImage([]), isFalse);
  });

  test('each site is fetched once, and never when turned off', () async {
    final asked = <String>[];
    final cache = FaviconCache(
      fetch: (host) async {
        asked.add(host);
        if (host == 'broken.example') throw StateError('network');
        return _png;
      },
    );

    expect(await cache.iconFor('https://example.com/a'), _png);
    expect(await cache.iconFor('https://www.example.com/b'), _png);
    expect(asked, ['example.com']);
    // A failed download is just a missing icon.
    expect(await cache.iconFor('https://broken.example'), isNull);
    expect(await cache.iconFor('http://localhost'), isNull);
    expect(asked, ['example.com', 'broken.example']);

    // Locking forgets the icons: they are fetched again afterwards.
    cache.clear();
    await cache.iconFor('https://example.com');
    expect(asked, hasLength(3));

    await cache.setEnabled(false);
    expect(await cache.iconFor('https://example.com'), isNull);
    expect(asked, hasLength(3));
  });

  testWidgets('a login shows its site icon; the settings turn icons off', (
    tester,
  ) async {
    useNarrowWindow(tester);
    final controller = VaultController(
      handle: FakeVaultHandle(),
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: FakeQuickUnlockStore(available: false),
    );
    await controller.create('master-password');
    controller.confirmEmergencyKit();
    await controller.save(login('GitHub', urls: ['https://github.com/login']));
    await controller.save(login('Offline'));

    final asked = <String>[];
    final cache = FaviconCache(
      fetch: (host) async {
        asked.add(host);
        return Uint8List.fromList(_png);
      },
    );
    await tester.pumpWidget(
      ArcanumApp(controller: controller, favicons: cache),
    );
    await tester.pump();

    // Only the login with a URL asks its site; the other keeps the key.
    expect(asked, ['github.com']);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.key), findsOneWidget);

    await tester.tap(find.byTooltip('Impostazioni'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Icone dei siti'), 200);
    await tester.tap(find.text('Icone dei siti'));
    await tester.pumpAndSettle();
    expect(cache.enabled, isFalse);
    Navigator.of(tester.element(find.byType(SwitchListTile))).pop();
    await tester.pumpAndSettle();

    expect(cache.enabled, isFalse);
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.key), findsNWidgets(2));
    expect(asked, ['github.com']);

    controller.dispose();
  });
}
