// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';

/// Monochrome palette — black, white, and greys ONLY.
///
/// Design rule: hierarchy comes from VALUE (lightness) and font weight, not hue.
/// Every old name (PRIMARY, ACCENT, SECONDARY, BTN_*, SUCCESS/WARNING/ERROR …)
/// is kept so existing references keep compiling — only the colour values change.
class AppColors {
  AppColors._();

  // ── Core ink & surface ──────────────────────────────────────────
  static const Color INK = Color(0xFF0A0A0A); // near-black: brand, buttons, app bars
  static const Color WHITE = Color(0xFFFFFFFF);
  static const Color BLACK = Color(0xFF0A0A0A); // softened black for text

  // ── Backgrounds ─────────────────────────────────────────────────
  static const Color LIGHT_BACKGROUND = Color(0xFFFAFAFA); // soft off-white so white cards lift
  static const Color DARK_BACKGROUND = Color(0xFF000000); // true black for dark mode

  // ── Grey scale (light → dark) ───────────────────────────────────
  static const Color GRAY_50 = Color(0xFFF5F5F5);
  static const Color GRAY_100 = Color(0xFFEEEEEE);
  static const Color GRAY_200 = Color(0xFFE0E0E0); // dividers / hairlines
  static const Color GRAY_300 = Color(0xFFCCCCCC); // inactive controls
  static const Color GRAY_400 = Color(0xFFADADAD);
  static const Color GRAY_500 = Color(0xFF8A8A8A); // muted text / icons
  static const Color GRAY_600 = Color(0xFF6B6B6B); // secondary text
  static const Color GRAY_700 = Color(0xFF4A4A4A);
  static const Color GRAY_800 = Color(0xFF2A2A2A);
  static const Color GRAY_900 = Color(0xFF1A1A1A); // elevated dark surface

  // ── Brand roles (kept for backwards-compatibility) ──────────────
  static const Color PRIMARY = INK; // was teal  → now near-black
  static const Color ACCENT = INK; // was amber → now near-black (CTAs)
  static const Color SECONDARY = GRAY_600; // muted supportive grey

  // ── Buttons / surfaces (legacy names) ───────────────────────────
  static const Color BTN_LIGHT = GRAY_100; // pale grey input/button bg (light)
  static const Color BTN_DARK = GRAY_900; // elevated dark surface
  static const Color GRAY = GRAY_200; // legacy divider name

  // ── Semantic — greyscale to honour "black & white only" ─────────
  // Errors/success no longer pop in colour. If you decide they should,
  // swap these three to the commented values on the right.
  static const Color SUCCESS = GRAY_900; // optional colour: Color(0xFF10B981)
  static const Color WARNING = GRAY_600; // optional colour: Color(0xFFF59E0B)
  static const Color ERROR = INK; //         optional colour: Color(0xFFD32F2F)

  // ── Helpers ─────────────────────────────────────────────────────
  static Color background({bool dark = false}) =>
      dark ? DARK_BACKGROUND : LIGHT_BACKGROUND;
  static Color button({bool dark = false}) => dark ? BTN_DARK : BTN_LIGHT;

  /// Monochrome swatch (greys) keyed off near-black.
  static MaterialColor primarySwatch() {
    return const MaterialColor(0xFF0A0A0A, <int, Color>{
      50: GRAY_50,
      100: GRAY_100,
      200: GRAY_200,
      300: GRAY_300,
      400: GRAY_400,
      500: GRAY_500,
      600: GRAY_600,
      700: GRAY_700,
      800: GRAY_800,
      900: GRAY_900,
    });
  }
}
