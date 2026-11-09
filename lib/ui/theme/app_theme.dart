import 'package:flutter/material.dart';

class AppTheme {
  static const Color bgDark = Color(0xFF0B0E17);
  static const Color cardDark = Color(0xFF151A28);
  static const Color cardElevated = Color(0xFF1E2538);
  static const Color primaryNeon = Color(0xFF7C4DFF);
  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color accentEmerald = Color(0xFF00E676);
  static const Color accentAmber = Color(0xFFFFAB00);
  static const Color accentRose = Color(0xFFFF5252);
  static const Color textPrimary = Color(0xFFF3F6FC);
  static const Color textSecondary = Color(0xFF9BA4B8);

  static ThemeData get darkStudioTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      colorScheme: const ColorScheme.dark(
        primary: primaryNeon,
        secondary: accentCyan,
        surface: cardDark,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accentCyan,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
        thumbColor: Colors.white,
        overlayColor: accentCyan.withValues(alpha: 0.2),
        trackHeight: 4.5,
      ),
    );
  }
}
