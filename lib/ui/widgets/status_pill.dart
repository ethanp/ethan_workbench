import 'package:flutter/material.dart';

import '../../deploy/deploy_job.dart';
import 'package:ethan_ui/ethan_ui.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.tone,
  });

  final String label;
  final EStatusTone tone;

  factory StatusPill.server({required bool running}) {
    if (running) {
      return const StatusPill(label: 'Listening', tone: EStatusTone.success);
    }
    return const StatusPill(label: 'Stopped', tone: EStatusTone.muted);
  }

  factory StatusPill.job(DeployJobStatus status) {
    return switch (status) {
      DeployJobStatus.queued =>
        const StatusPill(label: 'Queued', tone: EStatusTone.warning),
      DeployJobStatus.running =>
        const StatusPill(label: 'Running', tone: EStatusTone.accent),
      DeployJobStatus.succeeded =>
        const StatusPill(label: 'Succeeded', tone: EStatusTone.success),
      DeployJobStatus.failed =>
        const StatusPill(label: 'Failed', tone: EStatusTone.danger),
    };
  }

  @override
  Widget build(BuildContext context) {
    return EStatusChip(label: label, tone: tone, uppercase: true);
  }
}
