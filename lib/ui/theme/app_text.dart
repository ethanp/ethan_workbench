import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppText {
  static const title = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
    color: AppColors.textPrimary,
    height: 1.15,
  );

  static const projectName = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  static const section = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.15,
    color: AppColors.textPrimary,
    height: 1.25,
  );

  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.45,
  );

  static const caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 1.35,
  );

  static const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.7,
    color: AppColors.textMuted,
    height: 1.2,
  );

  static const mono = TextStyle(
    fontFamily: 'Menlo',
    fontFamilyFallback: ['Monaco', 'Courier', 'monospace'],
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    color: AppColors.mono,
    height: 1.45,
  );

  static const monoEmphasis = TextStyle(
    fontFamily: 'Menlo',
    fontFamilyFallback: ['Monaco', 'Courier', 'monospace'],
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    color: AppColors.accentGlow,
    height: 1.35,
  );
}
