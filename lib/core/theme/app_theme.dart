import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_spacing.dart';

abstract final class AppTheme {
  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.light(
          surface: AppColors.surface,
          primary: AppColors.sageGreen,
          onPrimary: Colors.white,
          secondary: AppColors.warmTaupe,
          onSecondary: Colors.white,
          onSurface: AppColors.warmBrown,
        ),
        textTheme: GoogleFonts.interTextTheme().copyWith(
          bodyLarge: const TextStyle(color: AppColors.darkOlive),
          bodyMedium: const TextStyle(color: AppColors.darkOlive),
        ),
        dividerColor: AppColors.divider,
        cardTheme: const CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppSpacing.cardRadius)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: AppColors.warmBrown,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: AppColors.warmBrown,
          contentTextStyle: TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
        ),
      );
}
