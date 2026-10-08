import 'package:flutter/material.dart';

class AppTheme {
  static const accent = Color(0xFF1B3A6B);
  static const accentDark = Color(0xFF7FA6E8);

  // Сепия (Охра)
  static const sepiaBg = Color(0xFFF1E7D0);
  static const sepiaCard = Color(0xFFEAE0C8);
  static const sepiaText = Color(0xFF3B2F1F);

  static ThemeData sepia() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      primary: accent,
      surface: sepiaCard,
      onSurface: sepiaText,
    ).copyWith(
      surface: sepiaCard,
      onSurface: sepiaText,
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent,
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: sepiaBg,
      cardColor: sepiaCard,
      dividerColor: sepiaText.withValues(alpha: 0.15),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: sepiaCard,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: sepiaText,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: sepiaCard,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: sepiaBg,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: sepiaCard,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: sepiaText,
        contentTextStyle: TextStyle(color: sepiaBg),
      ),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(primary: accent, secondary: accent);
    return _base(scheme).copyWith(scaffoldBackgroundColor: Colors.white);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accentDark,
      brightness: Brightness.dark,
    ).copyWith(primary: accentDark, secondary: accentDark);
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) => ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        cardTheme: CardThemeData(
          color: scheme.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: scheme.onSurface,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      );
}
