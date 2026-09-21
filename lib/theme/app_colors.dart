import 'package:flutter/material.dart';

class AppColors {
  // Core Canvas & Surfaces
  static const Color canvasBase = Color(0xFF0A0D14);
  static const Color surface1 = Color(0xFF101622);
  static const Color surface2 = Color(0xFF182234);
  
  static const Color surfaceBorder = Color(0x14FFFFFF); // ~0.08 alpha
  static const Color surfaceHighlightBorder = Color(0x4000F0FF); // ~0.25 alpha

  // Functional Accents
  static const Color electricCyan = Color(0xFF00F0FF);
  static const Color phosphorGreen = Color(0xFF05F19C);
  static const Color subtleAmber = Color(0xFFF59E0B);
  static const Color softCrimson = Color(0xFFEF4444);

  // Text & Metrics
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textDisabled = Color(0xFF475569);

  // Overlays / Translucent
  static const Color overlayGlass = Color(0xD1101622); // rgba(16, 22, 34, 0.82)
}
