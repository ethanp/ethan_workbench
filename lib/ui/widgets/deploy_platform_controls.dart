import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../../deploy/deploy_platform.dart';
import '../../projects/deployable_project.dart';
import 'package:ethan_ui/ethan_ui.dart';

extension DeployPlatformVisuals on DeployPlatform {
  IconData get icon => switch (this) {
        DeployPlatform.ios => Icons.phone_iphone_rounded,
        DeployPlatform.macos => Icons.desktop_mac_rounded,
      };

  Color get accent => switch (this) {
        DeployPlatform.ios => EColors.platformIos,
        DeployPlatform.macos => EColors.platformMacos,
      };

  Color get accentSoft => switch (this) {
        DeployPlatform.ios => EColors.platformIosSoft,
        DeployPlatform.macos => EColors.platformMacosSoft,
      };
}

/// Deploy-target controls: equal-width platform actions with status captions.
class DeployPlatformActionGroup extends StatelessWidget {
  const DeployPlatformActionGroup({
    super.key,
    required this.platforms,
    required this.onSelected,
    this.lastDeployedAt = const {},
    this.sourceStatus = const {},
  });

  final List<DeployPlatform> platforms;
  final ValueChanged<DeployPlatform> onSelected;
  final Map<DeployPlatform, DateTime?> lastDeployedAt;
  final Map<DeployPlatform, DeploySourceStatus> sourceStatus;

  @override
  Widget build(BuildContext context) {
    if (platforms.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (var index = 0; index < platforms.length; index++) ...[
          if (index > 0) const SizedBox(width: ELayout.spaceSm + 2),
          Expanded(
            child: ETintedAction(
              accent: platforms[index].accent,
              icon: platforms[index].icon,
              title: platforms[index].label,
              subtitle: _lastDeployedCaption(lastDeployedAt[platforms[index]]),
              chipLabel: _statusLabel(
                sourceStatus[platforms[index]] ??
                    DeploySourceStatus.unevaluated,
              ),
              chipTone: _statusTone(
                sourceStatus[platforms[index]] ??
                    DeploySourceStatus.unevaluated,
              ),
              onTap: () => onSelected(platforms[index]),
            ),
          ),
        ],
      ],
    );
  }

  static String? _statusLabel(DeploySourceStatus sourceStatus) =>
      switch (sourceStatus) {
        DeploySourceStatus.changed => 'changed',
        DeploySourceStatus.unchanged => 'current',
        DeploySourceStatus.neverDeployed => null,
        DeploySourceStatus.unevaluated => null,
      };

  static EStatusTone? _statusTone(DeploySourceStatus sourceStatus) =>
      switch (sourceStatus) {
        DeploySourceStatus.changed => EStatusTone.warning,
        DeploySourceStatus.unchanged => EStatusTone.success,
        DeploySourceStatus.neverDeployed => null,
        DeploySourceStatus.unevaluated => null,
      };

  static String _lastDeployedCaption(DateTime? deployedAt) {
    if (deployedAt != null) {
      return 'Deployed ${deployedAt.relativeTimeAgo()}';
    }
    return 'Never deployed';
  }
}

/// Compact platform identity for status headers and job summaries.
class DeployPlatformBadge extends StatelessWidget {
  const DeployPlatformBadge({super.key, required this.platform});

  final DeployPlatform platform;

  @override
  Widget build(BuildContext context) {
    return EStatusChip(
      label: platform.label,
      tone: platform == DeployPlatform.ios
          ? EStatusTone.accent
          : EStatusTone.muted,
      uppercase: true,
    );
  }
}
