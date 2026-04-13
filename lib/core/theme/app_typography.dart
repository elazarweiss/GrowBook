import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

abstract final class AppTypography {
  static TextStyle heading1 = GoogleFonts.playfairDisplay(
    fontSize: 32,
    fontWeight: FontWeight.w400,
    color: AppColors.warmBrown,
  );

  static TextStyle heading2 = GoogleFonts.playfairDisplay(
    fontSize: 24,
    fontWeight: FontWeight.w400,
    color: AppColors.warmBrown,
  );

  static TextStyle heading3 = GoogleFonts.playfairDisplay(
    fontSize: 20,
    fontWeight: FontWeight.w400,
    color: AppColors.warmBrown,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.darkOlive,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.darkOlive,
  );

  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.darkOlive,
    letterSpacing: 1.2,
  );

  static const TextStyle labelMuted = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.warmTaupe,
    letterSpacing: 1.2,
  );
}
