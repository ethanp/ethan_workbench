import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

abstract final class _DenseFusedWellSizing() {
  static const cellHeight = 44.0;
  static const cellPadH = 8.0;
  static const cellPadV = 6.0;
  static const statusEdgeHeight = 14.0;
  static const statusEdgeOverlap = 3.0;
  static const condensedMaxWidth = 92.0;
  static const condensedIconSize = 14.0;
  static const condensedGap = 2.0;
  static const condensedTrailingIdeal = 24.0;
  static const condensedTrailingMin = 14.0;
  static const railIconOnly = 28.0;
  static const railLabeled = 44.0;
  static const labeledRailMinClusterWidth = 168.0;
}

/// One tappable cell inside an [EActionCluster] well.
class const EActionClusterCell({
  required final IconData icon,
  required final String title,
  required final VoidCallback onActivated,
  final String? subtitle,

  /// Icon + this label when the cell is too narrow for title + subtitle.
  final String? condensedLabel,

  /// Hanging top-edge ribbon (e.g. `changed`). Not an inline chip.
  final String? statusLabel,
  final EStatusTone? statusTone,
  final Widget? trailing,
  final bool live = false,
});

/// Fused platform well: accent rail + hairline-split Run|Deploy cells.
class const EActionCluster({
  super.key,
  required final Color accent,
  required final List<EActionClusterCell> cells,
  final IconData? icon,
  final String? label,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();

    final height = _DenseFusedWellSizing.cellHeight + _DenseFusedWellSizing.cellPadV * 2;
    const radius = ELayout.borderRadiusMd;

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showRail = icon != null || (label != null && label!.isNotEmpty);
          final showRailLabel =
              showRail &&
              label != null &&
              label!.isNotEmpty &&
              constraints.maxWidth >= _DenseFusedWellSizing.labeledRailMinClusterWidth;
          final railWidth = !showRail
              ? 0.0
              : showRailLabel
              ? _DenseFusedWellSizing.railLabeled
              : _DenseFusedWellSizing.railIconOnly;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              ESurface(
                kind: ESurfaceKind.inset,
                borderRadius: radius,
                child: ClipRRect(
                  borderRadius: radius,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showRail)
                        _AccentRail(
                          accent: accent,
                          icon: icon,
                          label: showRailLabel ? label : null,
                          width: railWidth,
                        ),
                      for (var index = 0; index < cells.length; index++) ...[
                        if (index > 0)
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: EColors.border.withValues(alpha: 0.85),
                          ),
                        Expanded(
                          child: _Cell(accent: accent, cell: cells[index]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              ..._hangingEdges(
                clusterWidth: constraints.maxWidth,
                railWidth: railWidth,
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _hangingEdges({
    required double clusterWidth,
    required double railWidth,
  }) {
    final dividerTotal = cells.length > 1 ? (cells.length - 1).toDouble() : 0.0;
    final flexSpan = clusterWidth - railWidth - dividerTotal;
    if (flexSpan <= 0 || cells.isEmpty) return const [];

    final cellWidth = flexSpan / cells.length;
    var x = railWidth;
    final hangs = <Widget>[];
    for (var index = 0; index < cells.length; index++) {
      if (index > 0) x += 1;
      final cell = cells[index];
      final statusLabel = cell.statusLabel;
      final statusTone = cell.statusTone;
      if (statusLabel != null && statusTone != null) {
        hangs.add(
          Positioned(
            left: x,
            width: cellWidth,
            top:
                -_DenseFusedWellSizing.statusEdgeHeight +
                _DenseFusedWellSizing.statusEdgeOverlap,
            child: IgnorePointer(
              child: _StatusEdge(label: statusLabel, tone: statusTone),
            ),
          ),
        );
      }
      x += cellWidth;
    }
    return hangs;
  }
}

class const _AccentRail({
  required final Color accent,
  required final double width,
  final IconData? icon,
  final String? label,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: EColors.border.withValues(alpha: 0.85)),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: 0.18),
              accent.withValues(alpha: 0.06),
            ],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: label == null ? 4 : 6,
            vertical: 8,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) Icon(icon, size: 14, color: accent),
              if (icon != null && label != null) const SizedBox(height: 4),
              if (label != null)
                Text(
                  label!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EText.caption.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                    fontSize: ELayout.typeSize(9),
                    height: 1.0,
                    letterSpacing: 0.1,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _Cell({
  required final Color accent,
  required final EActionClusterCell cell,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cellAccent = cell.live ? accent : accent.withValues(alpha: 0.92);
    final tooltip = cell.subtitle == null || cell.subtitle!.isEmpty
        ? cell.title
        : '${cell.title} · ${cell.subtitle}';

    return Material(
      color: cell.live ? accent.withValues(alpha: 0.1) : Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: cell.onActivated,
          splashColor: accent.withValues(alpha: 0.14),
          highlightColor: accent.withValues(alpha: 0.06),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final condensed =
                  constraints.maxWidth <= _DenseFusedWellSizing.condensedMaxWidth;
              final padH = condensed
                  ? ELayout.spaceXs
                  : _DenseFusedWellSizing.cellPadH;
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: padH,
                  vertical: _DenseFusedWellSizing.cellPadV,
                ),
                child: SizedBox(
                  height: _DenseFusedWellSizing.cellHeight,
                  child: condensed
                      ? _iconAndCondensedLabel(
                          cellAccent,
                          contentWidth: math.max(
                            0.0,
                            constraints.maxWidth - padH * 2,
                          ),
                        )
                      : _titleAndSubtitle(cellAccent),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _titleAndSubtitle(Color cellAccent) {
    final showSubtitle = cell.subtitle != null && cell.subtitle!.isNotEmpty;
    return Row(
      children: [
        Icon(cell.icon, size: 15, color: cellAccent),
        const SizedBox(width: ELayout.spaceXs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                cell.title,
                style: EText.label.small.copyWith(
                  color: cellAccent,
                  letterSpacing: 0.2,
                  height: 1.15,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (showSubtitle)
                Text(
                  cell.subtitle!,
                  style: EText.caption.copyWith(
                    color: accent.withValues(alpha: 0.58),
                    fontSize: ELayout.typeSize(12),
                    height: 1.15,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
            ],
          ),
        ),
        if (cell.trailing != null) ...[
          const SizedBox(width: ELayout.spaceXs),
          cell.trailing!,
        ],
      ],
    );
  }

  Widget _iconAndCondensedLabel(
    Color cellAccent, {
    required double contentWidth,
  }) {
    if (contentWidth <= 0) return const SizedBox.shrink();

    final condensedLabel = cell.condensedLabel;
    final hasLabel = condensedLabel != null && condensedLabel.isNotEmpty;
    final trailing = cell.trailing;
    final icon = Icon(
      cell.icon,
      size: _DenseFusedWellSizing.condensedIconSize,
      color: cellAccent,
    );

    // Non-flex children get the full max width (Flexible flex:0 included).
    // Size trailing explicitly so Icon + gaps + trailing never exceed
    // [contentWidth]; drop the label first when space is tight.
    if (contentWidth < _DenseFusedWellSizing.condensedIconSize) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: icon,
      );
    }

    var used = _DenseFusedWellSizing.condensedIconSize;
    double? trailingWidth;
    if (trailing != null) {
      final availableForTrailing =
          contentWidth - used - _DenseFusedWellSizing.condensedGap;
      if (availableForTrailing >= _DenseFusedWellSizing.condensedTrailingMin) {
        trailingWidth = math.min(
          _DenseFusedWellSizing.condensedTrailingIdeal,
          availableForTrailing,
        );
        used += _DenseFusedWellSizing.condensedGap + trailingWidth;
      }
    }
    final showLabel =
        hasLabel && contentWidth - used - _DenseFusedWellSizing.condensedGap >= 8;

    return Row(
      children: [
        icon,
        if (showLabel) ...[
          const SizedBox(width: _DenseFusedWellSizing.condensedGap),
          Expanded(
            child: Text(
              condensedLabel,
              style: EText.label.small.copyWith(
                color: cellAccent,
                letterSpacing: 0.05,
                height: 1.1,
                fontSize: ELayout.typeSize(11),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
        if (trailingWidth != null) ...[
          const SizedBox(width: _DenseFusedWellSizing.condensedGap),
          SizedBox(
            width: trailingWidth,
            height: _DenseFusedWellSizing.condensedTrailingIdeal,
            child: FittedBox(fit: BoxFit.contain, child: trailing),
          ),
        ],
      ],
    );
  }
}

class const _StatusEdge({
  required final String label,
  required final EStatusTone tone,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.background.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        border: Border.all(color: tone.foreground.withValues(alpha: 0.4)),
      ),
      child: SizedBox(
        height: _DenseFusedWellSizing.statusEdgeHeight,
        child: Center(
          child: Text(
            label,
            style: EText.label.small.copyWith(
              color: tone.foreground,
              fontSize: ELayout.typeSize(9),
              letterSpacing: 0.6,
              height: 1.0,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
