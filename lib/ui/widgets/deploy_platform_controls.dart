import 'package:ethan_utils/ethan_utils.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import '../../deploy/deploy_job.dart';
import '../../deploy/deploy_platform.dart';
import '../../projects/deployable_project.dart';

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
      statusTone: ongoing.status.statusTone,
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
    statusLabel: sourceStatus.chipLabel,
    statusTone: sourceStatus.chipTone,
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
      tone: platform.badgeTone,
      uppercase: true,
    );
  }
}
