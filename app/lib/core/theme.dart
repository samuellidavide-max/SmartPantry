import 'package:flutter/material.dart';

/// Colori del brand: verde "risparmio" come accento, ambra per le promo.
class Brand {
  static const green = Color(0xFF146C43);
  static const greenDark = Color(0xFF4DC38B);
  static const promo = Color(0xFFA8500C);
  static const promoDark = Color(0xFFF0A15A);
  static const warn = Color(0xFF9A6B00);
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.green,
    brightness: brightness,
    primary: dark ? Brand.greenDark : Brand.green,
    surface: dark ? const Color(0xFF161E1A) : Colors.white,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
  return base.copyWith(
    scaffoldBackgroundColor: dark ? const Color(0xFF0D1210) : const Color(0xFFEEF2EF),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF0D1210) : const Color(0xFFEEF2EF),
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

extension ThemeX on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get saving => isDark ? Brand.greenDark : Brand.green;
  Color get promo => isDark ? Brand.promoDark : Brand.promo;
  Color get muted => Theme.of(this).colorScheme.onSurfaceVariant;
}
