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
    return StatusPill(label: status.pillLabel, tone: status.statusTone);
  }

  @override
  Widget build(BuildContext context) {
    return EStatusChip(label: label, tone: tone, uppercase: true);
  }
}
