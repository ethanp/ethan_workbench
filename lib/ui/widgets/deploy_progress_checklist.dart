import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ethan_ui/ethan_ui.dart';

import '../../deploy/deploy_checklist.dart';

/// Live checklist of deploy steps with an elapsed ticker on the active step.
class DeployProgressChecklist extends StatefulWidget {
  const DeployProgressChecklist({required this.items});

  final List<DeployChecklistItem> items;

  @override
  State<DeployProgressChecklist> createState() =>
      _DeployProgressChecklistState();
}

class _DeployProgressChecklistState extends State<DeployProgressChecklist> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant DeployProgressChecklist oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool get _hasActiveStep => widget.items.any(
    (item) => item.status == DeployChecklistItemStatus.active,
  );

  void _syncTicker() {
    if (!_hasActiveStep) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < widget.items.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          _checklistRow(widget.items[index]),
        ],
      ],
    );
  }

  Widget _checklistRow(DeployChecklistItem item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _statusIcon(item.status),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item.label,
            style: EText.body.copyWith(
              color: _labelColor(item.status),
              decoration: item.status == DeployChecklistItemStatus.skipped
                  ? TextDecoration.lineThrough
                  : null,
            ),
          ),
        ),
        if (item.status == DeployChecklistItemStatus.active &&
            item.startedAt != null)
          Text(
            DeployChecklist.formatElapsed(
              DateTime.now().difference(item.startedAt!),
            ),
            style: EText.mono.copyWith(color: EColors.accentGlow),
          ),
        if (item.status == DeployChecklistItemStatus.done &&
            item.startedAt != null &&
            item.finishedAt != null)
          Text(
            DeployChecklist.formatElapsed(
              item.finishedAt!.difference(item.startedAt!),
            ),
            style: EText.caption,
          ),
      ],
    );
  }

  Widget _statusIcon(DeployChecklistItemStatus status) {
    return switch (status) {
      DeployChecklistItemStatus.done => const Icon(
        Icons.check_circle_rounded,
        size: 18,
        color: EColors.success,
      ),
      DeployChecklistItemStatus.active => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      DeployChecklistItemStatus.skipped => const Icon(
        Icons.remove_circle_outline_rounded,
        size: 18,
        color: EColors.textMuted,
      ),
      DeployChecklistItemStatus.pending => Icon(
        Icons.radio_button_unchecked_rounded,
        size: 18,
        color: EColors.textMuted.withValues(alpha: 0.7),
      ),
    };
  }

  Color _labelColor(DeployChecklistItemStatus status) => switch (status) {
    DeployChecklistItemStatus.active => EColors.textPrimary,
    DeployChecklistItemStatus.done => EColors.textSecondary,
    DeployChecklistItemStatus.skipped => EColors.textMuted,
    DeployChecklistItemStatus.pending => EColors.textMuted,
  };
}
