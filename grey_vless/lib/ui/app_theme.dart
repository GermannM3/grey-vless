import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  static const bgTop = Color(0xFF0B1B3A);
  static const bgBottom = Color(0xFF1A1033);
  static const card = Color(0xFF162544);
  static const cardLight = Color(0xFF1E3158);
  static const accent = Color(0xFF3B82F6);
  static const accentGlow = Color(0xFF60A5FA);
  static const textPrimary = Color(0xFFF1F5F9);
  static const textMuted = Color(0xFF94A3B8);
  static const divider = Color(0xFF2A3F66);

  static ThemeData dark() {
    final scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: Colors.white,
      surface: card,
      onSurface: textPrimary,
      secondary: accentGlow,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bgBottom,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerColor: divider,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cardLight,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }

  static BoxDecoration get screenGradient => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bgTop, bgBottom],
        ),
      );

  static Color get statusOk => const Color(0xFF4ADE80);
  static Color get statusOff => textMuted;
  static Color get statusWarn => const Color(0xFFFBBF24);
  static Color get hint => textMuted;
}
