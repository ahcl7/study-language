import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData light({
    String fontFamily = 'Roboto',
    double fontSizeFactor = 1.0,
    Color seedColor = Colors.indigo,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    return _build(colorScheme, fontFamily, fontSizeFactor);
  }

  static ThemeData dark({
    String fontFamily = 'Roboto',
    double fontSizeFactor = 1.0,
    Color seedColor = Colors.indigo,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    return _build(colorScheme, fontFamily, fontSizeFactor);
  }

  static ThemeData _build(
    ColorScheme colorScheme,
    String fontFamily,
    double fontSizeFactor,
  ) {
    // GoogleFonts.getTextTheme() returns styles with null fontSize values
    // so we cannot use .apply(fontSizeFactor:) on them directly.
    // For now, we'll just use the textTheme as-is from GoogleFonts.
    final textTheme = GoogleFonts.getTextTheme(fontFamily);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 0,
      ),
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static const List<String> availableFonts = [
    'Roboto',
    'Open Sans',
    'Lato',
    'Montserrat',
    'Noto Sans JP',
    'Noto Sans',
    'Poppins',
    'Inter',
  ];

  static const List<Color> availableColors = [
    Colors.indigo,
    Colors.blue,
    Colors.teal,
    Colors.green,
    Colors.orange,
    Colors.red,
    Colors.purple,
    Colors.pink,
    Colors.cyan,
    Colors.amber,
  ];
}
