import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Theme of the app: compact on desktop, standard on phones, flat app bars
/// and 8 px shapes throughout.
ThemeData appTheme(Brightness brightness, {TargetPlatform? platform}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3F51B5),
    brightness: brightness,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  final desktop = switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => true,
    _ => false,
  };
  return ThemeData(
    colorScheme: scheme,
    visualDensity: desktop ? VisualDensity.compact : VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: shape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: shape),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: shape),
    ),
    chipTheme: ChipThemeData(shape: shape),
    cardTheme: CardThemeData(shape: shape),
    listTileTheme: ListTileThemeData(
      shape: shape,
      selectedTileColor: scheme.secondaryContainer,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
  );
}
