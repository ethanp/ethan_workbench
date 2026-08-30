import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

enum DeployPlatform({
  required final String label,
  required final IconData icon,
  required final Color accent,
  required final Color accentSoft,
  required final EStatusTone badgeTone,
}) {
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

  static DeployPlatform fromName(String name) {
    return DeployPlatform.values.firstWhere(
      (platform) => platform.name == name,
      orElse: () => DeployPlatform.ios,
    );
  }

  /// Argument passed to `deploy.rb`.
  String get scriptArgument => name;
}
