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

  test('surfaces are neutral gray, not tinted by the accent', () {
    bool gray(Color c) => (c.r - c.g).abs() < 0.02 && (c.g - c.b).abs() < 0.03;
    for (final b in Brightness.values) {
      final s = appTheme(b, platform: TargetPlatform.windows).colorScheme;
      for (final c in [
        s.surface,
        s.surfaceContainerLow,
        s.surfaceContainerHighest,
        s.outlineVariant,
        s.onSurface,
      ]) {
        expect(gray(c), isTrue, reason: '$b $c');
      }
      expect(s.surfaceContainerLow, isNot(s.surface));
    }
  });

  test('desktop text is one step smaller than touch text', () {
    final desktop = appTheme(
      Brightness.light,
      platform: TargetPlatform.windows,
    );
    final phone = appTheme(Brightness.light, platform: TargetPlatform.android);
    expect(desktop.textTheme.bodyLarge!.fontSize, 14);
    expect(desktop.textTheme.titleLarge!.fontWeight, FontWeight.w600);
    // Phones keep Material's own size, resolved from the typography.
    expect(phone.textTheme.bodyLarge!.fontSize, isNot(14));
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
