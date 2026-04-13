import 'package:flutter/material.dart';

abstract final class AppColors {
  // ── Base ────────────────────────────────────────────────────────────────────
  static const Color background = Color(0xFFFFFFFF); // pure white
  static const Color surface    = Color(0xFFF9FAFB); // near-white gray
  static const Color divider    = Color(0xFFE5E7EB); // clean light gray border

  // ── Text ────────────────────────────────────────────────────────────────────
  static const Color warmBrown = Color(0xFF111827); // near-black (primary text)
  static const Color darkOlive = Color(0xFF374151); // dark gray (body text)
  static const Color warmTaupe = Color(0xFF6B7280); // cool gray (muted text)

  // ── Accent ──────────────────────────────────────────────────────────────────
  static const Color sageGreen  = Color(0xFFF472B6); // modern rose-pink (primary action)
  static const Color sageMuted  = Color(0xFFFBCFE8); // soft pink tint
  static const Color softGold   = Color(0xFFFDE68A); // warm amber highlight
  static const Color accentSoft = Color(0xFFFDF2F8); // pink tint background

  // ── Baby timeline phases ─────────────────────────────────────────────────────
  static const Color babyBlush   = Color(0xFFFB7185); // vivid rose  (newborn)
  static const Color babyMint    = Color(0xFF34D399); // vivid mint  (infant)
  static const Color babySunrise = Color(0xFFFBBF24); // vivid amber (toddler)

  // ── Legacy / unused by GrowBook ─────────────────────────────────────────────
  static const Color trimesterSage     = Color(0xFF90C48A);
  static const Color trimesterLavender = Color(0xFFB8A0C0);
  static const Color trimesterHoney    = Color(0xFFCF9850);
  static const Color moodJoyful        = Color(0xFFFFD166);
  static const Color moodGrateful      = Color(0xFF8FA888);
  static const Color moodAnxious       = Color(0xFFE07A5F);
  static const Color moodTired         = Color(0xFFB5C4B1);
  static const Color moodPeaceful      = Color(0xFF81B29A);
  static const Color dayPast           = Color(0xFFEDC9C5);
  static const Color dayHasEntry       = Color(0xFFC5D9C1);
}
