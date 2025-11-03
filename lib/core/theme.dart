import 'package:flutter/material.dart';

const brandBlue = Color(0xFF0057D9);
const brandTeal = Color(0xFF00B8B0);
const brandNavy = Color(0xFF0B1F3A);

ThemeData buildAppTheme() {
  final baseScheme = ColorScheme.fromSeed(
    seedColor: brandBlue,
    brightness: Brightness.light,
  );
  final colorScheme = baseScheme.copyWith(
    primary: brandBlue,
    onPrimary: Colors.white,
    secondary: brandTeal,
    onSecondary: Colors.white,
    tertiary: brandTeal,
    surface: const Color(0xFFF6FAFD),
    onSurface: brandNavy,
    surfaceContainerHighest: const Color(0xFFE8F2FB),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    appBarTheme: AppBarTheme(
      backgroundColor: brandBlue,
      foregroundColor: colorScheme.onPrimary,
      elevation: 0,
      titleTextStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 20,
        color: Colors.white,
      ),
    ),
    scaffoldBackgroundColor: colorScheme.surface,
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: brandBlue.withValues(alpha: 0.12),
      backgroundColor: Colors.white,
      elevation: 4,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? brandBlue : brandNavy,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontWeight:
              states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? brandBlue : brandNavy,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: brandBlue,
        side: const BorderSide(color: brandBlue),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: brandBlue,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: brandBlue.withValues(alpha: 0.1),
      selectedColor: brandBlue.withValues(alpha: 0.18),
      labelStyle: const TextStyle(color: brandNavy),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: brandBlue,
      foregroundColor: Colors.white,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: brandBlue,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: brandBlue),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: brandBlue, width: 1.8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: brandBlue.withValues(alpha: 0.3)),
      ),
      filled: true,
      fillColor: Colors.white,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontWeight: FontWeight.w700,
        color: brandNavy,
      ),
      titleLarge: TextStyle(
        fontWeight: FontWeight.w700,
        color: brandNavy,
      ),
      titleMedium: TextStyle(
        fontWeight: FontWeight.w600,
        color: brandNavy,
      ),
      bodyLarge: TextStyle(
        color: brandNavy,
      ),
      bodyMedium: TextStyle(
        color: brandNavy,
      ),
    ),
  );
}
