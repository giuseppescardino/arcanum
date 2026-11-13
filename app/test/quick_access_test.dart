import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/quick_access.dart';
import 'package:arcanum/app/tools.dart';
import 'package:arcanum/app/vault_controller.dart';
import 'package:arcanum/ui/app.dart';

import 'fake_tools.dart';
import 'fakes.dart';
import 'window.dart';

void main() {
  setUp(() => tools = FakeTools());

  testWidgets('Enter in search copies the first match password', (
    tester,
  ) async {
    useNarrowWindow(tester);

    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        if (call.method == 'Clipboard.getData') {
          return {'text': clipboard};
        }
        return null;
      },
    );

    final controller = VaultController(
      handle: FakeVaultHandle(),
      secretKeys: MemorySecretKeyStore(),
      quickUnlock: FakeQuickUnlockStore(available: false),
    );
    await controller.create('master-password');
    controller.confirmEmergencyKit();
    await controller.save(login('Bank', password: 'bank-pw'));
    await controller.save(login('GitHub', password: 'gh-pw'));
    await tester.pumpWidget(ArcanumApp(controller: controller));

    // A shortcut request focuses the search field.
    QuickAccess.searchRequests.value++;
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField).first, 'git');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(clipboard, 'gh-pw');
    expect(find.textContaining('GitHub'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    controller.lock();
    // Let the 30 s clipboard-clearing timer fire.
    await tester.pump(const Duration(seconds: 31));
    expect(clipboard, '');
  });
}
