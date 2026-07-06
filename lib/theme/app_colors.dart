// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';

/// DAML unified palette: black, warm white, and a Spotify-style green accent.
/// Green is reserved for highlights, active states, icons, progress, and success.
class AppColors {
  AppColors._();

  static const Color GREEN = Color(0xFF1ED760);
  static const Color GREEN_DARK = Color(0xFF17A94B);
  static const Color GREEN_SOFT = Color(0xFFE8F8EE);

  static const Color INK = Color(0xFF0B0B0B);
  static const Color BLACK = Color(0xFF0B0B0B);
  static const Color WHITE = Color(0xFFFFFFFF);
  static const Color OFF_WHITE = Color(0xFFF7F7F4);

  static const Color LIGHT_BACKGROUND = OFF_WHITE;
  static const Color DARK_BACKGROUND = Color(0xFF000000);

  static const Color GRAY_50 = Color(0xFFF4F4F1);
  static const Color GRAY_100 = Color(0xFFEDEDE9);
  static const Color GRAY_200 = Color(0xFFDDDDD8);
  static const Color GRAY_300 = Color(0xFFC7C7C1);
  static const Color GRAY_400 = Color(0xFFA9A9A3);
  static const Color GRAY_500 = Color(0xFF85857F);
  static const Color GRAY_600 = Color(0xFF666661);
  static const Color GRAY_700 = Color(0xFF474743);
  static const Color GRAY_800 = Color(0xFF282826);
  static const Color GRAY_900 = Color(0xFF171716);

  static const Color PRIMARY = GREEN;
  static const Color ACCENT = GREEN;
  static const Color SECONDARY = INK;

  static const Color BTN_LIGHT = GRAY_100;
  static const Color BTN_DARK = GRAY_900;
  static const Color GRAY = GRAY_200;

  static const Color SUCCESS = GREEN;
  static const Color WARNING = Color(0xFFE6A700);
  static const Color ERROR = Color(0xFFD92D20);

  static Color background({bool dark = false}) =>
      dark ? DARK_BACKGROUND : LIGHT_BACKGROUND;
  static Color button({bool dark = false}) => dark ? BTN_DARK : BTN_LIGHT;

  static MaterialColor primarySwatch() {
    return const MaterialColor(0xFF1ED760, <int, Color>{
      50: Color(0xFFE8F8EE),
      100: Color(0xFFC7F0D5),
      200: Color(0xFF9FE7B8),
      300: Color(0xFF73DC98),
      400: Color(0xFF49D278),
      500: GREEN,
      600: GREEN_DARK,
      700: Color(0xFF128A3E),
      800: Color(0xFF0D6B31),
      900: Color(0xFF084B23),
    });
  }
}
