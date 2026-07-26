import 'package:flutter/material.dart';

import '../../deploy/deploy_job.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  factory StatusPill.server({required bool running}) {
    if (running) {
      return const StatusPill(
        label: 'Listening',
        foreground: AppColors.success,
        background: AppColors.successSoft,
      );
    }
    return const StatusPill(
      label: 'Stopped',
      foreground: AppColors.textMuted,
      background: AppColors.surfaceRaised,
    );
  }

  factory StatusPill.job(DeployJobStatus status) {
    return switch (status) {
      DeployJobStatus.queued => const StatusPill(
          label: 'Queued',
          foreground: AppColors.warning,
          background: AppColors.warningSoft,
        ),
      DeployJobStatus.running => const StatusPill(
          label: 'Running',
          foreground: AppColors.accentGlow,
          background: AppColors.accentSoft,
        ),
      DeployJobStatus.succeeded => const StatusPill(
          label: 'Succeeded',
          foreground: AppColors.success,
          background: AppColors.successSoft,
        ),
      DeployJobStatus.failed => const StatusPill(
          label: 'Failed',
          foreground: AppColors.danger,
          background: AppColors.dangerSoft,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label.toUpperCase(),
          style: AppText.label.copyWith(
            color: foreground,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}
