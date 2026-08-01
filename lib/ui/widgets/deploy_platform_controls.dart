import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../../deploy/deploy_platform.dart';
import '../../projects/deployable_project.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

extension DeployPlatformVisuals on DeployPlatform {
  IconData get icon => switch (this) {
        DeployPlatform.ios => Icons.phone_iphone_rounded,
        DeployPlatform.macos => Icons.desktop_mac_rounded,
      };

  Color get accent => switch (this) {
        DeployPlatform.ios => AppColors.platformIos,
        DeployPlatform.macos => AppColors.platformMacos,
      };

  Color get accentSoft => switch (this) {
        DeployPlatform.ios => AppColors.platformIosSoft,
        DeployPlatform.macos => AppColors.platformMacosSoft,
      };

  LinearGradient get actionGradient => switch (this) {
        DeployPlatform.ios => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF2A4A78),
              Color(0xFF1A2F4D),
            ],
          ),
        DeployPlatform.macos => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF3A4452),
              Color(0xFF252C36),
            ],
          ),
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
          if (index > 0) const SizedBox(width: 10),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        splashColor: platform.accent.withValues(alpha: 0.18),
        highlightColor: platform.accent.withValues(alpha: 0.08),
        child: Ink(
          decoration: BoxDecoration(
            gradient: platform.actionGradient,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: platform.accent.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: platform.accent.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Icon(platform.icon, size: 18, color: platform.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        platform.label,
                        style: AppText.section.copyWith(
                          color: platform.accent,
                          fontSize: 15,
                          letterSpacing: -0.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_statusPillLabel != null) ...[
                      const SizedBox(width: 8),
                      _SourceStatusPill(
                        label: _statusPillLabel!,
                        color: _statusPillColor,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _lastDeployedCaption,
                  style: AppText.caption.copyWith(
                    color: platform.accent.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Change-detection outcome — separate from last-deploy time.
  String? get _statusPillLabel => switch (sourceStatus) {
        DeploySourceStatus.changed => 'changed',
        DeploySourceStatus.unchanged => 'current',
        DeploySourceStatus.neverDeployed => null,
        DeploySourceStatus.unevaluated => null,
      };

  Color get _statusPillColor => switch (sourceStatus) {
        DeploySourceStatus.changed => AppColors.warning,
        DeploySourceStatus.unchanged => AppColors.success,
        DeploySourceStatus.neverDeployed => platform.accent,
        DeploySourceStatus.unevaluated => platform.accent,
      };

  String get _lastDeployedCaption {
    final deployedAt = lastDeployedAt;
    if (deployedAt != null) {
      return 'Deployed ${deployedAt.relativeTimeAgo()}';
    }
    return 'Never deployed';
  }
}

class _SourceStatusPill extends StatelessWidget {
  const _SourceStatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: AppText.label.copyWith(
            color: color,
            fontSize: 10,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// Compact platform identity for status headers and job summaries.
class DeployPlatformBadge extends StatelessWidget {
  const DeployPlatformBadge({
    super.key,
    required this.platform,
  });

  final DeployPlatform platform;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: platform.accentSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: platform.accent.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(platform.icon, size: 14, color: platform.accent),
            const SizedBox(width: 7),
            Text(
              platform.label.toUpperCase(),
              style: AppText.label.copyWith(
                color: platform.accent,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
