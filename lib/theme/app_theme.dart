// lib/theme/app_theme.dart
// ignore_for_file: deprecated_member_use, constant_identifier_names

import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => _buildLight();
  static ThemeData get darkTheme => _buildDark();

  static ThemeData _buildLight() {
    const colorScheme = ColorScheme.light(
      primary: AppColors.GREEN,
      onPrimary: AppColors.BLACK,
      secondary: AppColors.INK,
      onSecondary: AppColors.WHITE,
      background: AppColors.LIGHT_BACKGROUND,
      onBackground: AppColors.BLACK,
      surface: AppColors.WHITE,
      onSurface: AppColors.BLACK,
      error: AppColors.ERROR,
      onError: AppColors.WHITE,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.LIGHT_BACKGROUND,
      cardColor: AppColors.WHITE,
      dividerColor: AppColors.GRAY_200,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.LIGHT_BACKGROUND,
        foregroundColor: AppColors.INK,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.INK,
        ),
        iconTheme: IconThemeData(color: AppColors.GREEN),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.BLACK,
        displayColor: AppColors.BLACK,
      ),
      iconTheme: const IconThemeData(color: AppColors.GREEN),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.GREEN,
        linearTrackColor: AppColors.GREEN_SOFT,
        circularTrackColor: AppColors.GRAY_200,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.WHITE,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.GRAY_200),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.INK,
          foregroundColor: AppColors.WHITE,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.GREEN,
          foregroundColor: AppColors.BLACK,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.INK,
          backgroundColor: AppColors.WHITE,
          side: const BorderSide(color: AppColors.GRAY_300),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.GREEN_DARK),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.WHITE,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.GRAY_200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.GRAY_200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.GREEN, width: 1.7),
        ),
        prefixIconColor: AppColors.GREEN_DARK,
        suffixIconColor: AppColors.GREEN_DARK,
        hintStyle: const TextStyle(color: AppColors.GRAY_500),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.GREEN,
        foregroundColor: AppColors.BLACK,
        elevation: 2,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.INK,
        contentTextStyle: const TextStyle(color: AppColors.WHITE),
        actionTextColor: AppColors.GREEN,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.INK,
        indicatorColor: AppColors.GREEN,
        iconTheme: WidgetStatePropertyAll(IconThemeData(color: AppColors.WHITE)),
        labelTextStyle: WidgetStatePropertyAll(TextStyle(color: AppColors.WHITE)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.INK,
        selectedItemColor: AppColors.GREEN,
        unselectedItemColor: AppColors.GRAY_500,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w800),
        type: BottomNavigationBarType.fixed,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.GRAY_200,
        thickness: 1,
        space: 12,
      ),
    );
  }

  static ThemeData _buildDark() {
    const surface = Color(0xFF121212);
    const colorScheme = ColorScheme.dark(
      primary: AppColors.GREEN,
      onPrimary: AppColors.BLACK,
      secondary: AppColors.WHITE,
      onSecondary: AppColors.BLACK,
      background: AppColors.DARK_BACKGROUND,
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
      scaffoldBackgroundColor: AppColors.DARK_BACKGROUND,
      cardColor: surface,
      dividerColor: AppColors.GRAY_800,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.DARK_BACKGROUND,
        foregroundColor: AppColors.WHITE,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.WHITE,
        ),
        iconTheme: IconThemeData(color: AppColors.GREEN),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.WHITE,
        displayColor: AppColors.WHITE,
      ),
      iconTheme: const IconThemeData(color: AppColors.GREEN),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.GREEN,
        linearTrackColor: AppColors.GRAY_800,
        circularTrackColor: AppColors.GRAY_800,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.GRAY_800),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.GREEN,
          foregroundColor: AppColors.BLACK,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.GREEN,
          foregroundColor: AppColors.BLACK,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.WHITE,
          side: const BorderSide(color: AppColors.GRAY_700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.GREEN),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.GRAY_900,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.GRAY_800),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.GRAY_800),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.GREEN, width: 1.7),
        ),
        prefixIconColor: AppColors.GREEN,
        suffixIconColor: AppColors.GREEN,
        hintStyle: const TextStyle(color: AppColors.GRAY_500),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.GREEN,
        foregroundColor: AppColors.BLACK,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.GRAY_900,
        contentTextStyle: const TextStyle(color: AppColors.WHITE),
        actionTextColor: AppColors.GREEN,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.INK,
        selectedItemColor: AppColors.GREEN,
        unselectedItemColor: AppColors.GRAY_500,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w800),
        type: BottomNavigationBarType.fixed,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.GRAY_800,
        thickness: 1,
        space: 12,
      ),
    );
  }
}
