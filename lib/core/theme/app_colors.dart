import 'package:flutter/material.dart';

/// E-Labay colour palette: forest green primary, light green secondary,
/// off-white background, white cards and green/orange/red/blue status colours.
class AppColors {
  AppColors._();

  // Brand
  static const forestGreen = Color(0xFF1E6B3A);
  static const forestGreenDark = Color(0xFF134A27);
  static const lightGreen = Color(0xFF8BC34A);
  static const mintSurface = Color(0xFFE6F2E8);
  static const mintSurfaceStrong = Color(0xFFCDE6D2);

  // Neutrals
  static const background = Color(0xFFF5F7F5);
  static const card = Colors.white;
  static const border = Color(0xFFE3E8E4);
  static const textPrimary = Color(0xFF1C2620);
  static const textSecondary = Color(0xFF5E6B63);
  static const textMuted = Color(0xFF8C978F);

  // Status
  static const success = Color(0xFF2E8B47);
  static const warning = Color(0xFFE8890C);
  static const danger = Color(0xFFD93A3A);
  static const info = Color(0xFF2F6FDE);
  static const progress = Color(0xFF1C8C9E);
  static const rescheduled = Color(0xFF7A5AD8);

  // Leaderboard podium
  static const gold = Color(0xFFE2A80E);
  static const silver = Color(0xFF9AA5AE);
  static const bronze = Color(0xFFB8733A);

  /// Soft tinted background for a status/accent colour.
  static Color tint(Color color, [double alpha = 0.12]) =>
      color.withValues(alpha: alpha);
}
