import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens adapted from the provided HTML templates.
class AppTheme {
  static const Color primary = Color(0xFF13C8EC);
  static const Color bgDark = Color(0xFF101F22);
  static const Color bgLight = Color(0xFFF6F8F8);

  // Surfaces (templates vary slightly; keep a consistent set).
  static const Color surfaceDark = Color(0xFF16282C);
  static const Color surfaceDarker = Color(0xFF132023);
  static const Color surfaceLight = Color(0xFFFFFFFF);

  static const Color outlineDark = Color(0x1AFFFFFF); // ~white/10

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: primary,
        surface: surfaceLight,
        background: bgLight,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: bgLight,
      textTheme: _textTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.black.withOpacity(0.06)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.black.withOpacity(0.06),
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.black.withOpacity(0.03),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
      ).copyWith(
        primary: primary,
        background: bgDark,
        surface: surfaceDark,
        outline: outlineDark,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: bgDark,
      textTheme: _textTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: bgDark.withOpacity(0.92),
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: outlineDark),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0x1AFFFFFF),
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDarker,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceDarker,
        contentTextStyle: GoogleFonts.notoSans(color: Colors.white),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    final display = GoogleFonts.splineSansTextTheme(base);
    final body = GoogleFonts.notoSansTextTheme(base);

    // Merge: Spline Sans for headings, Noto Sans for body.
    return body.copyWith(
      displayLarge: display.displayLarge,
      displayMedium: display.displayMedium,
      displaySmall: display.displaySmall,
      headlineLarge: display.headlineLarge,
      headlineMedium: display.headlineMedium,
      headlineSmall: display.headlineSmall,
      titleLarge: display.titleLarge,
      titleMedium: display.titleMedium,
      titleSmall: display.titleSmall,
    );
  }
}
