import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens matching reelmaker-ai_login_alt and other templates exactly
class AppTheme {
  // Primary colors - exact from templates (#13c8ec)
  static const Color primary = Color(0xFF13c8ec);
  static const Color primaryDark = Color(0xFF0ea5c3);
  static const Color primaryHover = Color(0xFF14B8A6);
  
  // Background colors
  static const Color bgDark = Color(0xFF101f22);
  static const Color bgLight = Color(0xFFf6f8f8);
  
  // Surface colors - dark mode
  static const Color surfaceDark = Color(0xFF18282c);
  static const Color surfaceDarker = Color(0xFF132023);
  static const Color surfaceHighlight = Color(0xFF1a2c30);
  
  // Surface colors - light mode
  static const Color surfaceLight = Color(0xFFFFFFFF);
  
  // Border/outline
  static const Color outlineDark = Color(0x1AFFFFFF); // white/10
  static const Color borderLight = Color(0xFFE2E8F0);

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
      textTheme: _textTheme(base.textTheme, Brightness.light),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceLight,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24), // xl = 1.5rem
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
          borderRadius: BorderRadius.circular(16), // lg = 1rem
          borderSide: BorderSide.none,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: bgDark,
          minimumSize: const Size(0, 56), // h-14
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), // rounded-xl
          ),
          elevation: 0,
          shadowColor: primary.withOpacity(0.3),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
      textTheme: _textTheme(base.textTheme, Brightness.dark),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: bgDark.withOpacity(0.8),
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceDark,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24), // xl = 1.5rem (rounded-2xl)
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
          borderRadius: BorderRadius.circular(16), // rounded-xl
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceDarker,
        contentTextStyle: GoogleFonts.notoSans(color: Colors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: bgDark,
          minimumSize: const Size(0, 56), // h-14 from templates
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), // rounded-xl
          ),
          elevation: 0,
          shadowColor: primary.withOpacity(0.4),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 56),
          side: BorderSide(color: outlineDark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, Brightness brightness) {
    // Spline Sans for display/headings
    final display = GoogleFonts.splineSansTextTheme(base);
    // Noto Sans for body text
    final body = GoogleFonts.notoSansTextTheme(base);

    // Merge: Spline Sans for headings, Noto Sans for body
    return body.copyWith(
      displayLarge: display.displayLarge,
      displayMedium: display.displayMedium,
      displaySmall: display.displaySmall,
      headlineLarge: display.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.015,
      ),
      headlineMedium: display.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.015,
      ),
      headlineSmall: display.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleLarge: display.titleLarge?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -0.015,
      ),
      titleMedium: display.titleMedium?.copyWith(
        fontWeight: FontWeight.w900,
      ),
      titleSmall: display.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      // Body uses Noto Sans
      bodyLarge: body.bodyLarge?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: body.bodyMedium?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      bodySmall: body.bodySmall?.copyWith(
        fontWeight: FontWeight.w500,
      ),
    );
  }
  
  // Shadows matching templates
  static List<BoxShadow> get glowShadow => [
    BoxShadow(
      blurRadius: 20,
      spreadRadius: 0,
      color: primary.withOpacity(0.15),
    ),
  ];
  
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      blurRadius: 20,
      offset: const Offset(0, 4),
      color: Colors.black.withOpacity(0.2),
    ),
  ];
  
  static List<BoxShadow> get primaryShadow => [
    BoxShadow(
      blurRadius: 10,
      spreadRadius: 0,
      color: primary.withOpacity(0.4),
    ),
  ];
}
