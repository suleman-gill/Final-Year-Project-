import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ═══════════════════════════════════════════════════════════
// COLOR PALETTE — Premium Dark Slate & Emerald & Luxury Gold
// ═══════════════════════════════════════════════════════════
class AppColors {
  static bool isDarkMode = false;

  // Dark Theme Colors
  static const primary = Color(0xFF0F172A);      // Deep Slate
  static const secondary = Color(0xFF1E293B);    // Slate 800
  static Color get background => isDarkMode ? const Color(0xFF020617) : const Color(0xFFF8F6F0);   // Dynamic
  static Color get surface => isDarkMode ? const Color(0xFF111827) : const Color(0xFFFFFFFF);      // Dynamic
  
  // Luxury Accents
  static const gold = Color(0xFFD4AF37);         // Antique Gold
  static const goldLight = Color(0xFFF3E1A6);    // Shimmering Gold
  static const emerald = Color(0xFF10B981);      // Tajweed Emerald Green
  static const emeraldBg = Color(0x1F10B981);    // Light Emerald Background
  
  // Light Theme Colors (Clean & Classic Islamic vibe)
  static const bgCream = Color(0xFFF8FAFC);      // Soft Paper Cream (F8FAFC off-white)
  static const surfaceLight = Color(0xFFFFFFFF);
  static const primaryLight = Color(0xFF1E293B);
  
  // Text Colors
  static Color get textLight => isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);     // Dynamic
  static const textDark = Color(0xFF0F172A);      // Dark text
  static const textMuted = Color(0xFF64748B);     // Muted text
  
  // Feedback
  static const correct = Color(0xFF10B981);
  static const correctBg = Color(0x1510B981);
  static const incorrect = Color(0xFFEF4444);
  static const incorrectBg = Color(0x15EF4444);
  static const currentWord = Color(0xFFD4AF37);

  // Gradients
  static LinearGradient get luxuryDark => isDarkMode
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF020617)],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFCDEAEF), Color(0xFF86D2DF)], // Light cyan palette from user image
        );

  static const LinearGradient emeraldShine = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF059669), Color(0xFF10B981)],
  );

  static const LinearGradient goldShine = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB48A1E), Color(0xFFD4AF37), Color(0xFFF3E1A6)],
    stops: [0.0, 0.5, 1.0],
  );
}

// ═══════════════════════════════════════════════════════════
// TYPOGRAPHY
// ═══════════════════════════════════════════════════════════
class AppText {
  static TextStyle heading1({Color? color}) => GoogleFonts.outfit(
        fontSize: 26, 
        fontWeight: FontWeight.w800,
        color: color ?? AppColors.textLight,
      );

  static TextStyle heading2({Color? color}) => GoogleFonts.outfit(
        fontSize: 20, 
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.textLight,
      );

  static TextStyle heading3({Color? color}) => GoogleFonts.outfit(
        fontSize: 16, 
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.textLight,
      );

  static TextStyle body({Color? color}) => GoogleFonts.outfit(
        fontSize: 14, 
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textMuted,
      );

  static TextStyle caption({Color? color}) => GoogleFonts.outfit(
        fontSize: 11, 
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.textMuted,
        letterSpacing: 0.4,
      );

  // Arabic texts
  static const arabicLarge = TextStyle(
    fontFamily: 'Scheherazade',
    fontSize: 32, 
    height: 2.2,
  );

  static const arabicMedium = TextStyle(
    fontFamily: 'Scheherazade',
    fontSize: 24, 
    height: 2.0,
  );
}

// ═══════════════════════════════════════════════════════════
// APP THEMES
// ═══════════════════════════════════════════════════════════
class AppTheme {
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.dark(
          primary: AppColors.emerald,
          secondary: AppColors.gold,
          surface: AppColors.surface,
          background: AppColors.background,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: GoogleFonts.outfit(
            fontSize: 18, 
            fontWeight: FontWeight.w700,
            color: AppColors.textLight,
          ),
          iconTheme: IconThemeData(color: AppColors.textLight),
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
        ),
      );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.bgCream,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.gold,
          surface: AppColors.surfaceLight,
          background: AppColors.bgCream,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: GoogleFonts.outfit(
            fontSize: 18, 
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
          iconTheme: const IconThemeData(color: AppColors.textDark),
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme),
        cardTheme: const CardThemeData(
          color: AppColors.surfaceLight,
          elevation: 2,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════
// DIMENSIONS & SHADOWS
// ═══════════════════════════════════════════════════════════
class Dims {
  static const double pagePad  = 20.0;
  static const double cardPad  = 16.0;
  static const double radius   = 18.0;
  static const double radiusLg = 24.0;
  static const double radiusSm = 10.0;
}

class AppShadows {
  static const BoxShadow glass = BoxShadow(
    color: Color(0x1F000000),
    blurRadius: 16,
    offset: Offset(0, 8),
  );
}
