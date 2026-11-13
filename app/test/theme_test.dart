import 'package:arcanum/ui/site_icon.dart';
import 'package:arcanum/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop is compact, mobile is standard', () {
    for (final p in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      expect(
        appTheme(Brightness.light, platform: p).visualDensity,
        VisualDensity.compact,
      );
    }
    for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(
        appTheme(Brightness.light, platform: p).visualDensity,
        VisualDensity.standard,
      );
    }
  });

  test('flat app bar and 8 px shapes in both brightnesses', () {
    for (final b in Brightness.values) {
      final t = appTheme(b, platform: TargetPlatform.windows);
      expect(t.appBarTheme.scrolledUnderElevation, 0);
      expect(t.appBarTheme.backgroundColor, t.colorScheme.surface);
      final input = t.inputDecorationTheme.border as OutlineInputBorder;
      expect(input.borderRadius, BorderRadius.circular(8));
      expect(t.inputDecorationTheme.isDense, isTrue);
      expect(
        (t.dialogTheme.shape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(12),
      );
      expect(
        t.listTileTheme.selectedTileColor,
        t.colorScheme.secondaryContainer,
      );
      expect(t.dividerTheme.color, t.colorScheme.outlineVariant);
    }
  });

  testWidgets('the avatar stands out from a selected row', (tester) async {
    for (final b in Brightness.values) {
      final t = appTheme(b, platform: TargetPlatform.windows);
      await tester.pumpWidget(
        MaterialApp(
          theme: t,
          home: const Scaffold(body: ItemAvatar(child: Icon(Icons.key))),
        ),
      );
      final box =
          tester
                  .widget<Container>(
                    find.descendant(
                      of: find.byType(ItemAvatar),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(box.color, isNot(t.listTileTheme.selectedTileColor));
    }
  });
}
