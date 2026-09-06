import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/painting.dart';

import 'line_age_compact_tick.dart';
import 'line_age_histogram_emphasis.dart';
import 'line_age_histogram_geometry.dart';
import 'line_age_pane_title.dart';
import 'line_age_report.dart';

/// Shared pane marks: title, nice-Y rules, zero, compact counts, month names.
abstract class const LineAgeHistogramPane({
  required final LineAgeReport report,
  required final LineAgeHistogramGeometry geometry,
  required final LineAgeMonthColumns columns,
  required final NiceValueScale scale,
  required final LineAgeHistogramEmphasis emphasis,
}) {
  Rect get plot;
  double get titleY;
  String get title;

  double get titleMaxWidth => geometry.innerWidth;

  void paint(Canvas canvas) {
    _paintPaneTitle(canvas);
    paintBesidePaneTitle(canvas);
    _paintNiceYRules(canvas);
    _paintZeroBaseline(canvas);
    _paintCompactYCounts(canvas);
    _paintRotatedMonthNames(canvas);
    paintAlongMonths(canvas);
  }

  void paintBesidePaneTitle(Canvas canvas) {}

  void paintAlongMonths(Canvas canvas);

  void _paintPaneTitle(Canvas canvas) {
    LineAgePaneTitle(title).paint(
      canvas,
      Offset(geometry.margin.left, titleY),
      maxWidth: titleMaxWidth,
    );
  }

  void _paintNiceYRules(Canvas canvas) {
    if (scale.max <= 0) return;
    final paint = Paint()
      ..color = EColors.border.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (final tick in scale.ticks) {
      if (tick == 0) continue;
      final y = geometry.yInPlot(plot, tick, scale.max);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), paint);
    }
  }

  void _paintZeroBaseline(Canvas canvas) {
    canvas.drawLine(
      plot.bottomLeft,
      plot.bottomRight,
      Paint()
        ..color = EColors.borderStrong.withValues(alpha: 0.7)
        ..strokeWidth = 1,
    );
  }

  void _paintCompactYCounts(Canvas canvas) {
    if (scale.max <= 0) return;
    for (final tick in scale.ticks) {
      final label = LineAgeCompactTick.of(tick);
      label.paint(
        canvas,
        Offset(
          geometry.margin.left - label.width - 8,
          geometry.yInPlot(plot, tick, scale.max) - label.height / 2,
        ),
      );
    }
  }

  void _paintRotatedMonthNames(Canvas canvas) {
    for (
      var monthIndex = 0;
      monthIndex < report.timelineMonths.length;
      monthIndex++
    ) {
      final month = report.timelineMonths[monthIndex];
      final selected = emphasis.isSelected(month.month);
      final hovered = emphasis.isHovered(month.month);
      final label = TextPainter(
        text: TextSpan(
          text: month.shortMonthName,
          style: TextStyle(
            color: selected || hovered
                ? EColors.textPrimary
                : month.isEmpty
                ? EColors.textMuted.withValues(alpha: 0.55)
                : EColors.textMuted,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(columns.centerAt(monthIndex), plot.bottom + 8);
      canvas.rotate(-0.65);
      label.paint(canvas, Offset(-label.width / 2, 0));
      canvas.restore();
    }
  }
}
