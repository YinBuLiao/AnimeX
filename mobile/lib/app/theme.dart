import 'package:flutter/material.dart';

const _bg = Color(0xFF0F1014);
const _card = Color(0xFF1A1B22);
const _accent = Color(0xFFFF6B3D); // saturated orange-red

ThemeData animexLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: _accent,
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

ThemeData animexDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: _accent,
    brightness: Brightness.dark,
  ).copyWith(
    surface: _bg,
    surfaceContainer: _card,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: _bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: _bg,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(color: _card, elevation: 0),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: _card,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF2A2B33)),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
