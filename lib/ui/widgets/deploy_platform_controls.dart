import 'package:ethan_utils/ethan_utils.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import '../../deploy/deploy_job.dart';
import '../../deploy/deploy_platform.dart';
import '../../projects/deployable_project.dart';

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

/// Deploy cell for an [EActionCluster] under a platform rail.
EActionClusterCell deployActionCell({
  required DeployPlatform platform,
  required VoidCallback onSelected,
  DateTime? lastDeployedAt,
  DeploySourceStatus sourceStatus = DeploySourceStatus.unevaluated,
  DeployJob? ongoingDeploy,
  VoidCallback? onOpenOngoing,
}) {
  final ongoing = ongoingDeploy;
  final isThisDeployRunning =
      ongoing != null &&
      !ongoing.status.isTerminal &&
      ongoing.platform == platform;

  if (isThisDeployRunning) {
    return EActionClusterCell(
      icon: Icons.rocket_launch_rounded,
      title: 'Deploy',
      subtitle: 'In progress',
      condensedLabel: '…',
      statusLabel: ongoing.status.name,
      statusTone: ongoing.status == DeployJobStatus.queued
          ? EStatusTone.warning
          : EStatusTone.accent,
      live: true,
      onTap: onOpenOngoing ?? () {},
    );
  }

  return EActionClusterCell(
    icon: Icons.rocket_launch_rounded,
    title: 'Deploy',
    subtitle: lastDeployedAt != null
        ? lastDeployedAt.relativeTimeAgo()
        : 'Never',
    condensedLabel:
        lastDeployedAt != null ? lastDeployedAt.relativeTimeShort() : '—',
    statusLabel: switch (sourceStatus) {
      DeploySourceStatus.changed => 'changed',
      DeploySourceStatus.unchanged => 'current',
      DeploySourceStatus.neverDeployed ||
      DeploySourceStatus.unevaluated => null,
    },
    statusTone: switch (sourceStatus) {
      DeploySourceStatus.changed => EStatusTone.warning,
      DeploySourceStatus.unchanged => EStatusTone.success,
      DeploySourceStatus.neverDeployed ||
      DeploySourceStatus.unevaluated => null,
    },
    onTap: onSelected,
  );
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
