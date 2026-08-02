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
            child: _DeployPlatformAction(
              platform: platforms[index],
              lastDeployedAt: lastDeployedAt[platforms[index]],
              sourceStatus: sourceStatus[platforms[index]] ??
                  DeploySourceStatus.unevaluated,
              onPressed: () => onSelected(platforms[index]),
            ),
          ),
        ],
      ],
    );
  }
}

class _DeployPlatformAction extends StatelessWidget {
  const _DeployPlatformAction({
    required this.platform,
    required this.onPressed,
    required this.sourceStatus,
    this.lastDeployedAt,
  });

  final DeployPlatform platform;
  final VoidCallback onPressed;
  final DateTime? lastDeployedAt;
  final DeploySourceStatus sourceStatus;

  @override
  Widget build(BuildContext context) {
    return ESurface(
      kind: ESurfaceKind.tinted,
      accent: platform.accent,
      onTap: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(platform.icon, size: 18, color: platform.accent),
              const SizedBox(width: ELayout.spaceSm),
              Expanded(
                child: Text(
                  platform.label,
                  style: EText.section.copyWith(color: platform.accent),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_statusTone != null) ...[
                const SizedBox(width: ELayout.spaceSm),
                EStatusChip(label: _statusLabel!, tone: _statusTone!),
              ],
            ],
          ),
          const SizedBox(height: ELayout.spaceSm),
          Text(
            _lastDeployedCaption,
            style: EText.caption.copyWith(
              color: platform.accent.withValues(alpha: 0.62),
            ),
          ),
        ],
      ),
    );
  }

  String? get _statusLabel => switch (sourceStatus) {
        DeploySourceStatus.changed => 'changed',
        DeploySourceStatus.unchanged => 'current',
        DeploySourceStatus.neverDeployed => null,
        DeploySourceStatus.unevaluated => null,
      };

  EStatusTone? get _statusTone => switch (sourceStatus) {
        DeploySourceStatus.changed => EStatusTone.warning,
        DeploySourceStatus.unchanged => EStatusTone.success,
        DeploySourceStatus.neverDeployed => null,
        DeploySourceStatus.unevaluated => null,
      };

  String get _lastDeployedCaption {
    final deployedAt = lastDeployedAt;
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
