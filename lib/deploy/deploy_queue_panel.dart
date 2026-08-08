import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import 'deploy_checklist.dart';
import 'deploy_job.dart';

/// Right-rail queue: active deploy + FIFO wait list (+ optional job detail).
///
/// With a job detail open, the queue section is content-sized by default and
/// the queue/detail split can be resized by dragging the handle between them.
class DeployQueuePanel extends StatefulWidget {
  const DeployQueuePanel({
    super.key,
    required this.ongoing,
    required this.waiting,
    required this.onOpenOngoing,
    required this.onCancelWaiting,
    this.ongoingRemaining,
    this.jobDetail,
    this.width = 260,
  });

  final DeployJob? ongoing;
  final List<DeployJob> waiting;
  final VoidCallback onOpenOngoing;
  final Future<void> Function(String jobId) onCancelWaiting;

  /// Estimated time left for [ongoing] vs typical successful runs.
  final Duration? ongoingRemaining;

  /// Live deploy detail shown under the queue (Mac workbench).
  final Widget? jobDetail;
  final double width;

  @override
  State<DeployQueuePanel> createState() => _DeployQueuePanelState();
}

class _DeployQueuePanelState extends State<DeployQueuePanel> {
  static const _contentSizedQueueMaxHeight = 220.0;
  static const _queueMinHeight = 48.0;
  static const _jobDetailMinHeight = 160.0;

  /// Null until the split handle is first dragged; queue stays content-sized.
  double? _draggedQueueHeight;
  double _maxQueueHeight = _contentSizedQueueMaxHeight;
  final _queueSectionKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return ESidePanel(
      title: widget.jobDetail == null ? 'Queue' : 'Deploy',
      width: widget.width,
      child: widget.jobDetail == null
          ? _queueList(shrinkWrap: false)
          : _queueAndJobDetailSplit(),
    );
  }

  Widget _queueAndJobDetailSplit() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxQueueHeight = math.max(
          _queueMinHeight,
          constraints.maxHeight - _jobDetailMinHeight,
        );
        final draggedQueueHeight = _draggedQueueHeight?.clamp(
          _queueMinHeight,
          _maxQueueHeight,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (draggedQueueHeight != null)
              SizedBox(
                key: _queueSectionKey,
                height: draggedQueueHeight,
                child: _queueList(shrinkWrap: false),
              )
            else
              ConstrainedBox(
                key: _queueSectionKey,
                constraints: BoxConstraints(
                  maxHeight: math.min(
                    _contentSizedQueueMaxHeight,
                    _maxQueueHeight,
                  ),
                ),
                child: _queueList(shrinkWrap: true),
              ),
            _splitDragHandle(),
            Expanded(child: widget.jobDetail!),
          ],
        );
      },
    );
  }

  Widget _splitDragHandle() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _startSplitDrag,
        onVerticalDragUpdate: _updateSplitDrag,
        child: SizedBox(
          height: 11,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Divider(height: 1),
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: EColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startSplitDrag(DragStartDetails details) {
    final queueSectionBox =
        _queueSectionKey.currentContext?.findRenderObject() as RenderBox?;
    if (queueSectionBox == null) return;
    setState(() => _draggedQueueHeight = queueSectionBox.size.height);
  }

  void _updateSplitDrag(DragUpdateDetails details) {
    final queueHeight = _draggedQueueHeight;
    if (queueHeight == null) return;
    setState(() {
      _draggedQueueHeight = (queueHeight + details.delta.dy).clamp(
        _queueMinHeight,
        _maxQueueHeight,
      );
    });
  }

  Widget _queueList({required bool shrinkWrap}) {
    return ListView(
      shrinkWrap: shrinkWrap,
      padding: const EdgeInsets.fromLTRB(
        ELayout.spaceMd,
        0,
        ELayout.spaceMd,
        ELayout.spaceLg,
      ),
      children: [
        if (widget.ongoing != null) ...[
          Text('Now', style: EText.label),
          const SizedBox(height: ELayout.spaceSm),
          _QueueJobTile(
            job: widget.ongoing!,
            onTap: widget.onOpenOngoing,
            stageLabel: widget.ongoing!.activeStageLabel,
            remaining: widget.ongoingRemaining,
          ),
          const SizedBox(height: ELayout.spaceLg),
        ],
        Text('Up next', style: EText.label),
        const SizedBox(height: ELayout.spaceSm),
        if (widget.waiting.isEmpty)
          Text(
            'Nothing queued',
            style: EText.caption,
          )
        else
          for (var index = 0; index < widget.waiting.length; index++) ...[
            if (index > 0) const SizedBox(height: ELayout.spaceSm),
            _QueueJobTile(
              job: widget.waiting[index],
              position: index + 1,
              onCancel: () =>
                  widget.onCancelWaiting(widget.waiting[index].jobId),
            ),
          ],
      ],
    );
  }
}

class _QueueJobTile extends StatelessWidget {
  const _QueueJobTile({
    required this.job,
    this.position,
    this.onTap,
    this.onCancel,
    this.stageLabel,
    this.remaining,
  });

  final DeployJob job;
  final int? position;
  final VoidCallback? onTap;
  final VoidCallback? onCancel;
  final String? stageLabel;
  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    final platformLine = job.force
        ? '${job.platform.label} · force'
        : job.platform.label;
    final detailLine = stageLabel == null
        ? platformLine
        : '$platformLine · $stageLabel';
    final remainingLine = _remainingCaption(remaining);

    return ESurface(
      kind: ESurfaceKind.tinted,
      accent: job.platform.accent,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (position != null) ...[
            Text(
              '$position',
              style: EText.mono.copyWith(
                color: EColors.textMuted,
                fontSize: ELayout.typeSize(12),
              ),
            ),
            const SizedBox(width: ELayout.spaceSm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.projectName,
                  style: EText.label.copyWith(
                    color: EColors.textPrimary,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      job.platform.icon,
                      size: 12,
                      color: job.platform.accent,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        detailLine,
                        style: EText.caption.copyWith(
                          fontSize: ELayout.typeSize(11),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (remainingLine != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    remainingLine,
                    style: EText.caption.copyWith(
                      color: EColors.accentGlow,
                      fontSize: ELayout.typeSize(11),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (onCancel != null)
            IconButton(
              tooltip: 'Remove from queue',
              onPressed: onCancel,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
              color: EColors.textMuted,
            ),
        ],
      ),
    );
  }

  String? _remainingCaption(Duration? remaining) {
    if (remaining == null) return null;
    if (remaining > Duration.zero) {
      return '~${DeployChecklist.formatElapsed(remaining)} left';
    }
    // Past the typical wall time — only call it "wrapping up" on late stages.
    final stageId = _activeStageId(job);
    if (stageId == 'installing' ||
        stageId == 'recording' ||
        stageId == 'done') {
      return 'Wrapping up…';
    }
    return 'Taking longer than usual';
  }

  String? _activeStageId(DeployJob job) {
    for (final item in job.checklist) {
      if (item.status == DeployChecklistItemStatus.active) return item.id;
    }
    return null;
  }
}
