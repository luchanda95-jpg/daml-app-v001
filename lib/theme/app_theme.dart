// lib/theme/app_theme.dart
// ignore_for_file: deprecated_member_use, constant_identifier_names

import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Strict black / white / grey theme.
/// Light mode: near-black on off-white. Dark mode: white on true black.
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => _buildLight();
  static ThemeData get darkTheme => _buildDark();

  static ThemeData _buildLight() {
    const primary = AppColors.INK; // near-black brand
    const secondary = AppColors.GRAY_600; // muted grey (was amber)

    const colorScheme = ColorScheme.light(
      primary: primary,
      onPrimary: AppColors.WHITE,
      secondary: secondary,
      onSecondary: AppColors.WHITE,
      background: AppColors.LIGHT_BACKGROUND,
      onBackground: AppColors.BLACK,
      surface: AppColors.WHITE,
      onSurface: AppColors.BLACK,
      error: AppColors.ERROR,
      onError: AppColors.WHITE,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.LIGHT_BACKGROUND,
      cardColor: AppColors.WHITE,
      dividerColor: AppColors.GRAY_200,

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.WHITE, // clean white bar, dark text
        foregroundColor: AppColors.INK,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.INK,
        ),
        iconTheme: IconThemeData(color: AppColors.INK),
      ),

      textTheme: base.textTheme.apply(
        bodyColor: AppColors.BLACK,
        displayColor: AppColors.BLACK,
      ),

      iconTheme: const IconThemeData(color: AppColors.INK),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: AppColors.WHITE,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: AppColors.WHITE,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          backgroundColor: AppColors.WHITE,
          side: const BorderSide(color: AppColors.GRAY_300),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.INK),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.GRAY_50,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.GRAY_200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.INK, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.GRAY_500),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.INK,
        foregroundColor: AppColors.WHITE,
        elevation: 2,
      ),

      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.INK,
        contentTextStyle: TextStyle(color: AppColors.WHITE),
        behavior: SnackBarBehavior.floating,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.GRAY_200,
        thickness: 1,
        space: 12,
      ),
    );
  }

  static ThemeData _buildDark() {
    const bg = AppColors.DARK_BACKGROUND; // true black
    const surface = Color(0xFF121212);
    const divider = AppColors.GRAY_800;

    const colorScheme = ColorScheme.dark(
      primary: AppColors.WHITE,
      onPrimary: AppColors.BLACK,
      secondary: AppColors.WHITE,
      onSecondary: AppColors.BLACK,
      background: bg,
      onBackground: AppColors.WHITE,
      surface: surface,
      onSurface: AppColors.WHITE,
      error: AppColors.ERROR,
      onError: AppColors.WHITE,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: Typography.whiteMountainView,
    );

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      cardColor: surface,
      dividerColor: divider,

      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: AppColors.WHITE,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.WHITE,
        ),
        iconTheme: IconThemeData(color: AppColors.WHITE),
      ),

      textTheme: base.textTheme.apply(
        bodyColor: AppColors.WHITE,
        displayColor: AppColors.WHITE,
      ),

      iconTheme: const IconThemeData(color: AppColors.WHITE),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.WHITE,
          foregroundColor: AppColors.BLACK,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.WHITE,
          foregroundColor: AppColors.BLACK,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.WHITE,
          side: const BorderSide(color: Colors.white24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.WHITE),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.GRAY_800),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.WHITE, width: 1.5),
        ),
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.WHITE,
        foregroundColor: AppColors.BLACK,
        elevation: 2,
      ),

      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.WHITE,
        contentTextStyle: TextStyle(color: AppColors.BLACK),
        behavior: SnackBarBehavior.floating,
      ),

      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 12,
      ),
    );
  }
}
