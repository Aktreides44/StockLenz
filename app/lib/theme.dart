// The app's look in one place: colours, spacing, text sizes, corner radius and the phone breakpoint.
// Change a value here and it changes everywhere.
//
// Font: we use the platform's built-in font (Roboto on Android and the web, Segoe UI on Windows),
// so the app downloads no extra font files.
import 'package:flutter/material.dart';

/// The brand colour. Material 3 calculates all other colours (light and dark) from it.
const Color seedColor = Color(0xFF26A69A);

ThemeData buildTheme(Brightness brightness) {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness),
    visualDensity: VisualDensity.compact,
  );
}

/// Light grey behind the cards of the company page (in dark mode: the normal background).
Color pageBackground(ColorScheme colors) =>
    colors.brightness == Brightness.light ? const Color(0xFFF3F4F6) : colors.surface;

/// The cards themselves: white (in dark mode: slightly lighter than the background).
Color cardBackground(ColorScheme colors) =>
    colors.brightness == Brightness.light ? Colors.white : colors.surfaceContainer;

/// Spacing scale in logical pixels. Use these for padding and gaps instead of loose numbers.
abstract final class Space {
  static const double xxs = 2; // inside dense table cells and small chips
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

/// Text sizes. The dense screener table uses [body]; headings use the Material text theme.
abstract final class FontSizes {
  static const double tiny = 11; // chart axes, dates under fiscal years
  static const double small = 12; // labels and table headers
  static const double body = 13; // table cells and most text
  static const double medium = 14; // values in the summary
  static const double title = 15; // small headings (Pros / Cons)
  static const double large = 18; // big numbers
}

/// Corner radius for cards, boxes and buttons.
abstract final class Radii {
  static const double small = 4;
  static const double medium = 8;
}

/// Screens narrower than this (in logical pixels) get the phone layout.
/// Phones are about 360–430 wide, tablets from about 600.
const double phoneMaxWidth = 600;

bool isPhone(BuildContext context) => MediaQuery.sizeOf(context).width < phoneMaxWidth;
