import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/painting.dart';

import '../ui/workbench_action_accents.dart';
import 'line_age_directory_groups.dart';
import 'line_age_histogram_geometry.dart';
import 'line_age_histogram_pane.dart';
import 'line_age_report.dart';

/// Last-touched pane: stacked directory bars for each month.
class const LastTouchedMonthBars({
  required super.report,
  required super.geometry,
  required super.columns,
  required super.scale,
  required super.emphasis,
  required final LineAgeDirectoryLegend legend,
}) extends LineAgeHistogramPane {
  @override
  Rect get plot => geometry.lastTouchedPlot;

  @override
  double get titleY => geometry.lastTouchedPaneTitleY;

  @override
  String get title => 'Last-touched project source';

  @override
  void paintAlongMonths(Canvas canvas) {
    for (var monthIndex = 0; monthIndex < report.timelineMonths.length; monthIndex++) {
      _paintLastTouchedMonth(
        canvas,
        month: report.timelineMonths[monthIndex],
        x: columns.leftAt(monthIndex),
      );
    }
  }

  void _paintLastTouchedMonth(
    Canvas canvas, {
    required LineAgeMonth month,
    required double x,
  }) {
    if (month.isEmpty) {
      _paintEmptyLastTouchedMonth(canvas, x);
      return;
    }
    final stacks = legend.stacksForMonth(month);
    if (stacks.isEmpty) return;
    final barHeight = geometry.visibleBarHeight(month.totalLines, scale.max);
    if (barHeight <= 0) return;
    final barTop = geometry.yForVisibleBar(month.totalLines, scale.max);
    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, barTop, columns.width, barHeight),
      const Radius.circular(4),
    );
    canvas.save();
    canvas.clipRRect(barRect);
    _paintDirectoryStacks(canvas, month: month, stacks: stacks, x: x, barHeight: barHeight);
    canvas.restore();
    _strokeSelectedLastTouchedBar(canvas, barRect: barRect, month: month);
    _paintLastTouchedCountAboveBar(
      canvas,
      barTop: barTop,
      x: x,
      month: month,
    );
  }

  void _paintDirectoryStacks(
    Canvas canvas, {
    required LineAgeMonth month,
    required List<({String key, int lineCount})> stacks,
    required double x,
    required double barHeight,
  }) {
    if (geometry.segmentHeight(month.totalLines, scale.max) <
        LineAgeHistogramGeometry.minVisibleBarHeight) {
      _paintMinimumVisibleLastTouchedBar(
        canvas,
        month: month,
        stacks: stacks,
        x: x,
        barHeight: barHeight,
      );
      return;
    }
    var yBottom = geometry.lastTouchedPlot.bottom;
    for (final stack in stacks) {
      final height = barHeight * (stack.lineCount / month.totalLines);
      if (height < 0.5) {
        yBottom -= height;
        continue;
      }
      final yTop = yBottom - height;
      final directoryEmphasized = emphasis.isEmphasized(stack.key);
      canvas.drawRect(
        Rect.fromLTWH(x, yTop, columns.width, height),
        Paint()
          ..color = legend
              .colorForKey(stack.key)
              .withValues(
                alpha: emphasis.opacityDimUnemphasizedAndUnselected(
                  directoryEmphasized: directoryEmphasized,
                  yearMonth: month.month,
                ),
              ),
      );
      if (height > 2.5 && directoryEmphasized) {
        canvas.drawLine(
          Offset(x, yTop),
          Offset(x + columns.width, yTop),
          Paint()
            ..color = EColors.surface.withValues(alpha: 0.45)
            ..strokeWidth = 1,
        );
      }
      yBottom = yTop;
    }
  }

  void _paintMinimumVisibleLastTouchedBar(
    Canvas canvas, {
    required LineAgeMonth month,
    required List<({String key, int lineCount})> stacks,
    required double x,
    required double barHeight,
  }) {
    canvas.drawRect(
      Rect.fromLTWH(
        x,
        geometry.yForVisibleBar(month.totalLines, scale.max),
        columns.width,
        barHeight,
      ),
      Paint()
        ..color = legend
            .colorForKey(stacks.first.key)
            .withValues(
              alpha: emphasis.opacityDimUnemphasizedAndUnselected(
                directoryEmphasized: emphasis.isEmphasized(stacks.first.key),
                yearMonth: month.month,
              ),
            ),
    );
  }

  void _paintEmptyLastTouchedMonth(Canvas canvas, double x) {
    const slotHeight = 3.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x,
          geometry.lastTouchedPlot.bottom - slotHeight,
          columns.width,
          slotHeight,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = EColors.borderStrong.withValues(alpha: 0.28),
    );
  }

  void _strokeSelectedLastTouchedBar(
    Canvas canvas, {
    required RRect barRect,
    required LineAgeMonth month,
  }) {
    if (!emphasis.isSelected(month.month)) return;
    canvas.drawRRect(
      barRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = WorkbenchActionAccents.lineAge.withValues(alpha: 0.95),
    );
  }

  void _paintLastTouchedCountAboveBar(
    Canvas canvas, {
    required double barTop,
    required double x,
    required LineAgeMonth month,
  }) {
    final valueLabel = TextPainter(
      text: TextSpan(
        text: month.totalLines.asCompactCount,
        style: TextStyle(
          color: emphasis.isSelected(month.month) || emphasis.isHovered(month.month)
              ? EColors.textPrimary
              : EColors.textMuted,
          fontSize: 11,
          fontWeight: emphasis.isSelected(month.month)
              ? FontWeight.w600
              : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    valueLabel.paint(
      canvas,
      Offset(x + columns.width / 2 - valueLabel.width / 2, barTop - 16),
    );
  }
}
