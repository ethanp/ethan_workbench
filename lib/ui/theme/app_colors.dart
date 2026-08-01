import 'package:flutter/material.dart';

/// Palette keyed to the skeuomorphic app icon: graphite metal, signal blue, success green.
abstract final class AppColors {
  static const background = Color(0xFF0C0E11);
  static const backgroundLift = Color(0xFF151820);
  static const surface = Color(0xFF1A1E26);
  static const surfaceRaised = Color(0xFF242A34);
  static const surfaceInset = Color(0xFF0E1116);

  static const border = Color(0xFF2A313C);
  static const borderStrong = Color(0xFF3D4756);
  static const borderGlow = Color(0xFF3B4A63);

  static const textPrimary = Color(0xFFF4F6F9);
  static const textSecondary = Color(0xFFB7C0CE);
  static const textMuted = Color(0xFF7E8898);

  static const accent = Color(0xFF3B82F6);
  static const accentSoft = Color(0xFF1A2F4D);
  static const accentGlow = Color(0xFF60A5FA);

  /// iOS deploy target — signal blue (phone).
  static const platformIos = accentGlow;
  static const platformIosSoft = accentSoft;

  /// macOS deploy target — cool silver (desktop), contrasts the blue phone target.
  static const platformMacos = Color(0xFFD5DEE9);
  static const platformMacosSoft = Color(0xFF2A323E);

  static const success = Color(0xFF34D399);
  static const successSoft = Color(0xFF163528);
  static const warning = Color(0xFFFBBF24);
  static const warningSoft = Color(0xFF3A2E12);
  static const danger = Color(0xFFF87171);
  static const dangerSoft = Color(0xFF3A1A1A);

  static const mono = Color(0xFFD1D9E6);

  static const scaffoldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF12161E),
      background,
      Color(0xFF0A0C10),
    ],
    stops: [0.0, 0.45, 1.0],
  );

  static const ambientGlowGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x332563EB),
      Color(0x000C0E11),
    ],
  );

  static const panelGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF222833),
      Color(0xFF171B22),
    ],
  );

  static const rowGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1F2530),
      Color(0xFF161A21),
    ],
  );
}
