import 'package:flutter/material.dart';

abstract final class ReaduoColors {
  static const accent = Color(0xFF365BDB);
  static const accentTint = Color(0xFFEDF2FF);
  static const ink = Color(0xFF172237);
  static const muted = Color(0xFF58667B);
  static const line = Color(0xFFE3E8F0);
  static const background = Color(0xFFF7F9FC);
  static const paper = Colors.white;
}

abstract final class ReaduoSpacing {
  static const screenHorizontal = 12.0;
  static const small = 8.0;
  static const medium = 16.0;
  static const large = 24.0;
}

abstract final class ReaduoRadii {
  static const button = 12.0;
  static const logo = 17.0;
}

abstract final class ReaduoTheme {
  static ThemeData get modern {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: ReaduoColors.accent,
      brightness: Brightness.light,
      surface: ReaduoColors.paper,
    ).copyWith(primary: ReaduoColors.accent, secondary: ReaduoColors.accent);

    return ThemeData(
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: ReaduoColors.ink,
        ),
        titleSpacing: ReaduoSpacing.screenHorizontal,
      ),
      colorScheme: colorScheme,
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: ReaduoColors.accent,
        foregroundColor: Colors.white,
      ),
      scaffoldBackgroundColor: ReaduoColors.background,
      inputDecorationTheme: const InputDecorationTheme(
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: ReaduoColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: ReaduoColors.accent),
        ),
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: ReaduoColors.ink,
          fontSize: 38,
          height: 1.12,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.1,
        ),
        bodyLarge: TextStyle(
          color: ReaduoColors.muted,
          fontSize: 16,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          color: ReaduoColors.muted,
          fontSize: 12,
          height: 1.5,
        ),
        labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: ReaduoColors.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ReaduoRadii.button),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: ReaduoColors.ink,
          backgroundColor: ReaduoColors.paper,
          side: const BorderSide(color: ReaduoColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ReaduoRadii.button),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: ReaduoColors.accent,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ReaduoColors.ink,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
    );
  }
}
