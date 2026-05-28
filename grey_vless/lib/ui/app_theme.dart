import 'package:flutter/material.dart';

/// Мягкая светлая тема — ближе к GTK Adwaita, без резкого чёрного фона.
class AppTheme {
  static const _surface = Color(0xFFF4F5F7);
  static const _card = Color(0xFFFFFFFF);
  static const _primary = Color(0xFF4A6FA5);
  static const _text = Color(0xFF2C3338);
  static const _muted = Color(0xFF6B7280);

  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: _primary,
      brightness: Brightness.light,
      surface: _surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: base.copyWith(
        primary: _primary,
        onPrimary: Colors.white,
        surface: _surface,
        onSurface: _text,
      ),
      scaffoldBackgroundColor: _surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: _card,
        foregroundColor: _text,
        elevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: _text,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: _card,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _card,
        hintStyle: const TextStyle(color: _muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: _card,
        selectedColor: Color(0xFFDCE6F5),
        labelStyle: TextStyle(color: _text),
      ),
    );
  }

  static Color get statusOk => const Color(0xFF2E7D4A);
  static Color get statusOff => _muted;
  static Color get hint => _muted;
}
