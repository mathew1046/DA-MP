import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class Palette {
  static const paper = Color(0xFFF5F3EE);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1B1D1C);
  static const muted = Color(0xFF6A6E6B);
  static const line = Color(0xFFE2DED5);
  static const accent = Color(0xFF2F5D50);
  static const accentSoft = Color(0xFFDDE8E3);
  static const freeze = Color(0xFFB5523B);
  static const freezeSoft = Color(0xFFF3DED7);
  static const still = Color(0xFF8C8F8A);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.accent,
    surface: Palette.paper,
  ).copyWith(
    primary: Palette.accent,
    onPrimary: Colors.white,
    secondary: Palette.accent,
    error: Palette.freeze,
    surface: Palette.paper,
    onSurface: Palette.ink,
    surfaceContainerLowest: Palette.surface,
    surfaceContainerLow: Palette.surface,
    outlineVariant: Palette.line,
  );

  final text = Typography.material2021(platform: defaultTargetPlatform).black.merge(const TextTheme(
    displayMedium: TextStyle(fontSize: 64, fontWeight: FontWeight.w300, letterSpacing: -1.5, height: 1.05),
    headlineMedium: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, letterSpacing: -0.5, height: 1.2),
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.2, height: 1.25),
    titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, height: 1.3),
    titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3),
    bodyLarge: TextStyle(fontSize: 19, height: 1.45),
    bodyMedium: TextStyle(fontSize: 17, height: 1.45),
    bodySmall: TextStyle(fontSize: 15, height: 1.4),
    labelLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.2),
  ));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.paper,
    textTheme: text.apply(bodyColor: Palette.ink, displayColor: Palette.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: Palette.paper,
      foregroundColor: Palette.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(color: Palette.ink),
    ),
    cardTheme: const CardThemeData(
      color: Palette.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: Palette.line),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Palette.line, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        foregroundColor: Palette.ink,
        side: const BorderSide(color: Palette.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Palette.accent, textStyle: text.titleMedium, minimumSize: const Size(48, 48)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Palette.surface,
      indicatorColor: Palette.accentSoft,
      height: 76,
      labelTextStyle: WidgetStateProperty.all(text.labelMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: Palette.ink)),
      iconTheme: WidgetStateProperty.all(const IconThemeData(size: 28, color: Palette.ink)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size(0, 52)),
        textStyle: WidgetStateProperty.all(text.titleMedium?.copyWith(fontSize: 16)),
        side: WidgetStateProperty.all(const BorderSide(color: Palette.line)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : Palette.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.accent : Palette.line),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
  );
}
