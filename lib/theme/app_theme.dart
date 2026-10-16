import 'package:flutter/material.dart';

class AppTheme {
  // Slate / Dark theme palette
  static const Color darkScaffold = Color(0xFF0F172A);
  static const Color darkCard = Color(0xFF1E293B);
  static const Color darkCardBorder = Color(0xFF334155);
  static const Color darkPrimary = Color(0xFF38BDF8); // Sky blue
  static const Color darkSecondary = Color(0xFF818CF8); // Indigo

  // Clean / Light theme palette
  static const Color lightScaffold = Color(0xFFF1F5F9); // Crisp slate-50/100
  static const Color lightCard = Colors.white;
  static const Color lightCardBorder = Color(0xFFE2E8F0); // slate-200
  static const Color lightPrimary = Color(0xFF0284C7); // Sky-600
  static const Color lightSecondary = Color(0xFF4F46E5); // Indigo-600

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkScaffold,
      colorScheme: const ColorScheme.dark(
        primary: darkPrimary,
        secondary: darkSecondary,
        surface: darkCard,
        onSurface: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkCardBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkScaffold,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkCard,
        indicatorColor: darkPrimary.withValues(alpha: 0.2),
        elevation: 8,
      ),
      dividerTheme: const DividerThemeData(
        color: Colors.white10,
        thickness: 1,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightScaffold,
      colorScheme: const ColorScheme.light(
        primary: lightPrimary,
        secondary: lightSecondary,
        surface: lightCard,
        onSurface: Color(0xFF0F172A),
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lightCardBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightScaffold,
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: lightCard,
        indicatorColor: lightPrimary.withValues(alpha: 0.15),
        elevation: 8,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE2E8F0),
        thickness: 1,
      ),
    );
  }
}

class AppColors {
  final bool isDark;

  const AppColors(this.isDark);

  factory AppColors.of(BuildContext context) {
    return AppColors(Theme.of(context).brightness == Brightness.dark);
  }

  Color get scaffoldBg => isDark ? AppTheme.darkScaffold : AppTheme.lightScaffold;
  Color get cardBg => isDark ? AppTheme.darkCard : AppTheme.lightCard;
  Color get cardBorder => isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder;
  Color get surfaceBg => isDark ? const Color(0xFF1E293B) : Colors.white;

  Color get surface => surfaceBg;
  Color get card => cardBg;
  Color get background => scaffoldBg;

  Color get textPrimary => isDark ? Colors.white : const Color(0xFF0F172A);
  Color get textSecondary => isDark ? Colors.white70 : const Color(0xFF475569);
  Color get textMuted => isDark ? Colors.white38 : const Color(0xFF94A3B8);

  Color get divider => isDark ? Colors.white10 : const Color(0xFFE2E8F0);
  Color get border => isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);

  Color get inputBg => isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get inputBorder => isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);

  Color get primary => isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary;
  Color get secondary => isDark ? AppTheme.darkSecondary : AppTheme.lightSecondary;

  Color get chipBg => isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get chipBorder => isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

  Color get navBarBg => isDark ? AppTheme.darkCard : Colors.white;
  Color get navBarSelectedIcon => isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary;
  Color get navBarUnselectedIcon => isDark ? Colors.white60 : const Color(0xFF64748B);

  Color get audioProgressBg => isDark ? Colors.white12 : const Color(0xFFE2E8F0);
  Color get subCardBg => isDark ? const Color(0xFF0F172A).withValues(alpha: 0.5) : const Color(0xFFF8FAFC);
}
