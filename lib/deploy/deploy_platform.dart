import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

enum DeployPlatform {
  ios(
    label: 'iOS',
    icon: Icons.phone_iphone_rounded,
    accent: EColors.platformIos,
    accentSoft: EColors.platformIosSoft,
    badgeTone: EStatusTone.accent,
  ),
  macos(
    label: 'macOS',
    icon: Icons.desktop_mac_rounded,
    accent: EColors.platformMacos,
    accentSoft: EColors.platformMacosSoft,
    badgeTone: EStatusTone.muted,
  );

  const DeployPlatform({
    required this.label,
    required this.icon,
    required this.accent,
    required this.accentSoft,
    required this.badgeTone,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final Color accentSoft;
  final EStatusTone badgeTone;

  static DeployPlatform fromName(String name) {
    return DeployPlatform.values.firstWhere(
      (platform) => platform.name == name,
      orElse: () => DeployPlatform.ios,
    );
  }

  /// Argument passed to `deploy.rb`.
  String get scriptArgument => name;
}
