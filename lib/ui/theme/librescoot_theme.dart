import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class LibrescootColors {
  static const accentLight = Color(0xFF087889);
  static const accentDark = Color(0xFF3DD8E8);
  static const accentBright = Color(0xFF22D3EE);
  static const charcoal = Color(0xFF2A2D30);
  static const ink = Color(0xFF111111);
  static const canvasLight = Color(0xFFF4F6F8);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceRaisedLight = Color(0xFFEDF0F3);
  static const borderLight = Color(0xFFD4D8DC);
  static const borderStrongLight = Color(0xFFA0A4A8);

  static const canvasDark = Color(0xFF0A0A0A);
  static const surfaceDark = Color(0xFF141414);
  static const surfaceRaisedDark = Color(0xFF1E1E1E);
  static const borderDark = Color(0xFF222222);
  static const borderStrongDark = Color(0xFF3A3A3A);
}

ThemeData buildLibrescootTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? _darkScheme : _lightScheme;
  final textTheme = _textTheme(brightness);
  final radius = BorderRadius.circular(6);
  final compactRadius = BorderRadius.circular(4);

  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? LibrescootColors.canvasDark : LibrescootColors.canvasLight,
    textTheme: textTheme,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: LibrescootColors.charcoal,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.primary,
      textColor: scheme.onSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      titleTextStyle: textTheme.titleMedium?.copyWith(color: scheme.onSurface),
      subtitleTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
      shape: RoundedRectangleBorder(borderRadius: compactRadius),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? scheme.primary : scheme.surfaceContainerHighest,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? scheme.onPrimary : scheme.outline,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? scheme.primary : scheme.outline,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? scheme.primary : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(scheme.onPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? scheme.primary : scheme.outline,
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
      secondaryActiveTrackColor: scheme.primary.withValues(alpha: 0.35),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: scheme.surfaceContainerHighest,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: compactRadius),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: compactRadius),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: compactRadius),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: compactRadius),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurface,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: compactRadius),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: compactRadius)),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurface,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.primary : scheme.surface,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: compactRadius, borderSide: BorderSide(color: scheme.outline)),
      enabledBorder: OutlineInputBorder(borderRadius: compactRadius, borderSide: BorderSide(color: scheme.outline)),
      focusedBorder:
          OutlineInputBorder(borderRadius: compactRadius, borderSide: BorderSide(color: scheme.primary, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: compactRadius, borderSide: BorderSide(color: scheme.error)),
      focusedErrorBorder:
          OutlineInputBorder(borderRadius: compactRadius, borderSide: BorderSide(color: scheme.error, width: 2)),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: scheme.primary,
      collapsedIconColor: scheme.primary,
      textColor: scheme.onSurface,
      collapsedTextColor: scheme.onSurface,
      shape: RoundedRectangleBorder(borderRadius: compactRadius),
      collapsedShape: RoundedRectangleBorder(borderRadius: compactRadius),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: LibrescootColors.charcoal,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: compactRadius),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: scheme.surface,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: scheme.outlineVariant),
      shape: const StadiumBorder(),
      labelStyle: textTheme.labelMedium,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: LibrescootColors.charcoal, borderRadius: compactRadius),
      textStyle: textTheme.bodySmall?.copyWith(color: Colors.white),
    ),
  );
}

TextTheme _textTheme(Brightness brightness) {
  final inter = ThemeData(brightness: brightness).textTheme.apply(fontFamily: 'Inter');
  return inter.copyWith(
    displayLarge: inter.displayLarge?.copyWith(fontFamily: 'Abel'),
    displayMedium: inter.displayMedium?.copyWith(fontFamily: 'Abel'),
    displaySmall: inter.displaySmall?.copyWith(fontFamily: 'Abel'),
    titleLarge: inter.titleLarge?.copyWith(fontWeight: FontWeight.w500),
    titleMedium: inter.titleMedium?.copyWith(fontWeight: FontWeight.w500),
    titleSmall: inter.titleSmall?.copyWith(fontWeight: FontWeight.w500),
  );
}

const _lightScheme = ColorScheme.light(
  primary: LibrescootColors.accentLight,
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFD7F2F5),
  onPrimaryContainer: Color(0xFF063D46),
  secondary: LibrescootColors.charcoal,
  onSecondary: Colors.white,
  secondaryContainer: Color(0xFFE4E7EA),
  onSecondaryContainer: LibrescootColors.ink,
  tertiary: Color(0xFF1E40AF),
  onTertiary: Colors.white,
  error: Color(0xFF991B1B),
  onError: Colors.white,
  errorContainer: Color(0xFFFEE2E2),
  onErrorContainer: Color(0xFF7F1D1D),
  surface: LibrescootColors.surfaceLight,
  onSurface: LibrescootColors.ink,
  onSurfaceVariant: Color(0xFF555555),
  surfaceContainerLowest: LibrescootColors.surfaceLight,
  surfaceContainerLow: LibrescootColors.canvasLight,
  surfaceContainer: LibrescootColors.surfaceRaisedLight,
  surfaceContainerHigh: Color(0xFFE8EAED),
  surfaceContainerHighest: LibrescootColors.borderLight,
  outline: LibrescootColors.borderStrongLight,
  outlineVariant: LibrescootColors.borderLight,
  shadow: Colors.black,
  scrim: Colors.black,
);

const _darkScheme = ColorScheme.dark(
  primary: LibrescootColors.accentDark,
  onPrimary: Color(0xFF00363D),
  primaryContainer: Color(0xFF124C54),
  onPrimaryContainer: Color(0xFFB9F5FB),
  secondary: Color(0xFFF0F0F0),
  onSecondary: LibrescootColors.ink,
  secondaryContainer: LibrescootColors.surfaceRaisedDark,
  onSecondaryContainer: Color(0xFFF0F0F0),
  tertiary: Color(0xFF60A5FA),
  onTertiary: Color(0xFF071A33),
  error: Color(0xFFFB7185),
  onError: Color(0xFF3F0712),
  errorContainer: Color(0xFF4C101B),
  onErrorContainer: Color(0xFFFFD9DE),
  surface: LibrescootColors.surfaceDark,
  onSurface: Color(0xFFF0F0F0),
  onSurfaceVariant: Color(0xFF999999),
  surfaceContainerLowest: LibrescootColors.canvasDark,
  surfaceContainerLow: LibrescootColors.surfaceDark,
  surfaceContainer: LibrescootColors.surfaceRaisedDark,
  surfaceContainerHigh: Color(0xFF242424),
  surfaceContainerHighest: Color(0xFF2C2C2C),
  outline: LibrescootColors.borderStrongDark,
  outlineVariant: LibrescootColors.borderDark,
  shadow: Colors.black,
  scrim: Colors.black,
);
