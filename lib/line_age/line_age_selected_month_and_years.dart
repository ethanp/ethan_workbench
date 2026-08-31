import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/painting.dart';

import '../ui/workbench_action_accents.dart';
import 'line_age_histogram_emphasis.dart';
import 'line_age_histogram_geometry.dart';
import 'line_age_report.dart';

/// Selected-month column through both panes, and years under last-touched.
class const LineAgeSelectedMonthAndYears({
  required final LineAgeReport report,
  required final LineAgeHistogramGeometry geometry,
  required final LineAgeMonthColumns columns,
  required final LineAgeHistogramEmphasis emphasis,
}) {
  void paint(Canvas canvas) {
    _paintSelectedMonthThroughPanes(canvas);
    _paintYearBoundariesThroughPanes(canvas);
    _paintYearsUnderLastTouched(canvas);
  }

  void _paintSelectedMonthThroughPanes(Canvas canvas) {
    for (var monthIndex = 0; monthIndex < report.timelineMonths.length; monthIndex++) {
      final month = report.timelineMonths[monthIndex];
      final isSelected = emphasis.isSelected(month.month);
      final isHovered = emphasis.isHovered(month.month);
      if (!isSelected && !isHovered) continue;
      final x = columns.leftAt(monthIndex);
      canvas.drawRect(
        Rect.fromLTRB(
          x,
          geometry.sizePlot.top,
          x + columns.width,
          geometry.lastTouchedPlot.bottom,
        ),
        Paint()
          ..color = WorkbenchActionAccents.lineAge.withValues(
            alpha: isSelected ? 0.12 : 0.06,
          ),
      );
    }
  }

  void _paintYearBoundariesThroughPanes(Canvas canvas) {
    final bands = report.yearBands;
    if (bands.length < 2) return;
    final paint = Paint()
      ..color = EColors.borderStrong.withValues(alpha: 0.42)
      ..strokeWidth = 1;
    final baselineY = geometry.lastTouchedPlot.bottom;
    for (var bandIndex = 1; bandIndex < bands.length; bandIndex++) {
      final previous = bands[bandIndex - 1];
      final next = bands[bandIndex];
      final x =
          (columns.rightAt(previous.lastMonthIndex) +
              columns.leftAt(next.firstMonthIndex)) /
          2;
      canvas.drawLine(
        Offset(x, geometry.sizePlot.top),
        Offset(x, baselineY + 34),
        paint,
      );
    }
  }

  void _paintYearsUnderLastTouched(Canvas canvas) {
    final baselineY = geometry.lastTouchedPlot.bottom;
    for (final band in report.yearBands) {
      final left = columns.leftAt(band.firstMonthIndex);
      final right = columns.rightAt(band.lastMonthIndex);
      final label = TextPainter(
        text: TextSpan(
          text: '${band.year}',
          style: const TextStyle(
            color: EColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset((left + right) / 2 - label.width / 2, baselineY + 38),
      );
    }
  }
}
