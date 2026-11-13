import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Neutral surfaces with one blue accent, after the "three columns" mockup:
/// white and light-gray planes, hairline borders, the accent kept for the
/// selection and the primary action.
ColorScheme _scheme(Brightness brightness) {
  const accent = Color(0xFF3B5BDB);
  final base = ColorScheme.fromSeed(seedColor: accent, brightness: brightness);
  if (brightness == Brightness.light) {
    return base.copyWith(
      primary: accent,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE8EDFD),
      onPrimaryContainer: const Color(0xFF1C2F7A),
      secondary: const Color(0xFF52525B),
      secondaryContainer: const Color(0xFFE8EDFD),
      onSecondaryContainer: const Color(0xFF1C2F7A),
      tertiary: const Color(0xFFB45309),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFFEF3C7),
      onTertiaryContainer: const Color(0xFF78350F),
      error: const Color(0xFFC62828),
      errorContainer: const Color(0xFFFDECEC),
      onErrorContainer: const Color(0xFF8A1C1C),
      surface: Colors.white,
      onSurface: const Color(0xFF18181B),
      onSurfaceVariant: const Color(0xFF5F6068),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF7F7F8),
      surfaceContainer: const Color(0xFFF2F2F4),
      surfaceContainerHigh: const Color(0xFFECECEF),
      surfaceContainerHighest: const Color(0xFFE6E6EA),
      outline: const Color(0xFFA1A1AA),
      outlineVariant: const Color(0xFFE4E4E7),
      inverseSurface: const Color(0xFF27272A),
      onInverseSurface: const Color(0xFFF4F4F5),
      surfaceTint: Colors.transparent,
    );
  }
  return base.copyWith(
    primary: const Color(0xFF8EA4F7),
    onPrimary: const Color(0xFF0F1D4D),
    primaryContainer: const Color(0xFF26335E),
    onPrimaryContainer: const Color(0xFFDCE3FD),
    secondary: const Color(0xFFA1A1AA),
    secondaryContainer: const Color(0xFF26335E),
    onSecondaryContainer: const Color(0xFFDCE3FD),
    tertiary: const Color(0xFFF0B35B),
    onTertiary: const Color(0xFF3B2300),
    tertiaryContainer: const Color(0xFF4A3410),
    onTertiaryContainer: const Color(0xFFFDE6BF),
    error: const Color(0xFFF28B82),
    errorContainer: const Color(0xFF4A1C1C),
    onErrorContainer: const Color(0xFFFCDADA),
    surface: const Color(0xFF18181B),
    onSurface: const Color(0xFFECECEE),
    onSurfaceVariant: const Color(0xFFA1A1AA),
    surfaceContainerLowest: const Color(0xFF111113),
    surfaceContainerLow: const Color(0xFF1E1E21),
    surfaceContainer: const Color(0xFF232327),
    surfaceContainerHigh: const Color(0xFF2A2A2E),
    surfaceContainerHighest: const Color(0xFF313136),
    outline: const Color(0xFF63636B),
    outlineVariant: const Color(0xFF2E2E33),
    inverseSurface: const Color(0xFFECECEE),
    onInverseSurface: const Color(0xFF18181B),
    surfaceTint: Colors.transparent,
  );
}

/// Theme of the app: neutral surfaces and one accent everywhere; on desktop
/// also compact sizes (14 px body text, 36 px controls) for mouse use.
ThemeData appTheme(Brightness brightness, {TargetPlatform? platform}) {
  final scheme = _scheme(brightness);
  final desktop = switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => true,
    _ => false,
  };
  final radius = BorderRadius.circular(8);
  final shape = RoundedRectangleBorder(borderRadius: radius);
  final base = ThemeData(
    colorScheme: scheme,
    platform: platform,
    visualDensity: desktop ? VisualDensity.compact : VisualDensity.standard,
  );
  final text = _textTheme(base.textTheme, scheme, desktop: desktop);
  final controlHeight = desktop ? 36.0 : 44.0;
  final buttonPadding = EdgeInsets.symmetric(horizontal: desktop ? 14 : 18);
  final hairline = BorderSide(color: scheme.outlineVariant);

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    iconTheme: IconThemeData(
      size: desktop ? 20 : 24,
      color: scheme.onSurfaceVariant,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: desktop ? 56 : 60,
      titleSpacing: desktop ? 20 : 16,
      titleTextStyle: text.titleLarge,
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
      actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
      shape: Border(bottom: hairline),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surface,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: desktop ? 10 : 14,
      ),
      hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      labelStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
      border: OutlineInputBorder(borderRadius: radius),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape,
        minimumSize: Size(0, controlHeight),
        padding: buttonPadding,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        minimumSize: Size(0, controlHeight),
        padding: buttonPadding,
        textStyle: text.labelLarge,
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: shape,
        minimumSize: Size(0, controlHeight),
        padding: buttonPadding,
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        iconSize: desktop ? 18 : 22,
        shape: shape,
        visualDensity: desktop ? VisualDensity.compact : null,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      highlightElevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      extendedTextStyle: text.labelLarge,
    ),
    chipTheme: ChipThemeData(
      shape: shape,
      side: hairline,
      backgroundColor: scheme.surface,
      selectedColor: scheme.secondaryContainer,
      labelStyle: text.bodyMedium,
      secondaryLabelStyle: text.bodyMedium?.copyWith(
        color: scheme.onSecondaryContainer,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      showCheckmark: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: hairline,
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: shape,
      selectedTileColor: scheme.secondaryContainer,
      selectedColor: scheme.onSecondaryContainer,
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      subtitleTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      leadingAndTrailingTextStyle: text.labelMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      horizontalTitleGap: 12,
      minLeadingWidth: 0,
      minVerticalPadding: desktop ? 6 : 8,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyLarge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      textStyle: text.bodyLarge,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: radius, side: hairline),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: desktop ? 420 : null,
      shape: shape,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      waitDuration: const Duration(milliseconds: 400),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
  );
}

/// Desktop text runs one step smaller than Material's touch sizes, with
/// semibold titles; phones keep Material's sizes.
TextTheme _textTheme(
  TextTheme base,
  ColorScheme scheme, {
  required bool desktop,
}) {
  TextStyle? s(TextStyle? t, double size, FontWeight weight) => t?.copyWith(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: 0,
    height: 1.35,
  );
  final themed = base.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  if (!desktop) {
    return themed.copyWith(
      titleLarge: themed.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: themed.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
  return themed.copyWith(
    headlineSmall: s(themed.headlineSmall, 22, FontWeight.w600),
    titleLarge: s(themed.titleLarge, 18, FontWeight.w600),
    titleMedium: s(themed.titleMedium, 15, FontWeight.w600),
    titleSmall: s(themed.titleSmall, 13, FontWeight.w600),
    bodyLarge: s(themed.bodyLarge, 14, FontWeight.w400),
    bodyMedium: s(themed.bodyMedium, 13, FontWeight.w400),
    bodySmall: s(themed.bodySmall, 12, FontWeight.w400),
    labelLarge: s(themed.labelLarge, 13, FontWeight.w500),
    labelMedium: s(themed.labelMedium, 12, FontWeight.w500),
    labelSmall: s(themed.labelSmall, 11, FontWeight.w500),
  );
}
