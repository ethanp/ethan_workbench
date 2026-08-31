import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/painting.dart';

import '../ui/workbench_action_accents.dart';
import 'line_age_histogram_pane.dart';
import 'line_age_report.dart';

/// Project size at month-end / as of today, cubic through the month-end dots.
class const ProjectSizePane({
  required super.report,
  required super.geometry,
  required super.columns,
  required super.scale,
  required super.emphasis,
}) extends LineAgeHistogramPane {
  @override
  Rect get plot => geometry.sizePlot;

  @override
  double get titleY => geometry.sizePaneTitleY;

  @override
  String get title => 'Project size at month-end';

  @override
  double get titleMaxWidth => geometry.innerWidth * 0.62;

  @override
  void paintBesidePaneTitle(Canvas canvas) {
    final caption = _asOfTodayOrMonthEndCaption();
    if (caption == null) return;
    final label = TextPainter(
      text: TextSpan(
        text: caption,
        style: const TextStyle(
          color: WorkbenchActionAccents.lineAge,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset(plot.right - label.width, titleY),
    );
  }

  String? _asOfTodayOrMonthEndCaption() {
    final latestMonth = _latestMonthWithProjectSize();
    if (latestMonth == null) return null;
    final projectSize = report.projectSizeByMonth.at(latestMonth.month);
    if (projectSize == null) return null;
    final compact = projectSize.asCompactCount;
    if (latestMonth.month == DateTime.now().yearMonthKey) {
      return '$compact as of today';
    }
    return compact;
  }

  LineAgeMonth? _latestMonthWithProjectSize() {
    for (final month in report.timelineMonths.reversed) {
      final sizeAtMonth = report.projectSizeByMonth.at(month.month);
      if (sizeAtMonth != null && sizeAtMonth > 0) return month;
    }
    return null;
  }

  @override
  void paintAlongMonths(Canvas canvas) {
    final monthEnds = _monthEnds();
    if (monthEnds.isEmpty) return;
    final points = [for (final monthEnd in monthEnds) monthEnd.at];
    _paintHeightAsTranslucency(canvas, points);
    _strokeCubicThroughMonthEnds(canvas, points);
    _paintMonthEndDots(canvas, monthEnds);
    _paintProjectSizeAboveMonthEnds(canvas, monthEnds);
  }

  List<_MonthEndProjectSize> _monthEnds() {
    final monthEnds = <_MonthEndProjectSize>[];
    for (var monthIndex = 0; monthIndex < report.timelineMonths.length; monthIndex++) {
      final month = report.timelineMonths[monthIndex];
      final projectSize = report.projectSizeByMonth.at(month.month);
      if (projectSize == null || projectSize <= 0) continue;
      monthEnds.add(
        _MonthEndProjectSize(
          at: Offset(
            columns.centerAt(monthIndex),
            geometry.yInPlot(plot, projectSize, scale.max),
          ),
          month: month,
          projectSize: projectSize,
        ),
      );
    }
    return monthEnds;
  }

  void _paintHeightAsTranslucency(Canvas canvas, List<Offset> points) {
    final path = _cubicThroughMonthEnds(points)
      ..lineTo(points.last.dx, plot.bottom)
      ..lineTo(points.first.dx, plot.bottom)
      ..close();
    canvas.save();
    canvas.clipRect(plot);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            WorkbenchActionAccents.lineAge.withValues(alpha: 0.30),
            WorkbenchActionAccents.lineAge.withValues(alpha: 0.05),
            WorkbenchActionAccents.lineAge.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.7, 1.0],
        ).createShader(plot),
    );
    canvas.restore();
  }

  void _strokeCubicThroughMonthEnds(Canvas canvas, List<Offset> points) {
    canvas.drawPath(
      _cubicThroughMonthEnds(points),
      Paint()
        ..color = WorkbenchActionAccents.lineAge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Path _cubicThroughMonthEnds(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final span = (current.dx - previous.dx) / 3;
      path.cubicTo(
        previous.dx + span,
        previous.dy,
        current.dx - span,
        current.dy,
        current.dx,
        current.dy,
      );
    }
    return path;
  }

  void _paintMonthEndDots(Canvas canvas, List<_MonthEndProjectSize> monthEnds) {
    final fill = Paint()..color = WorkbenchActionAccents.lineAge;
    for (final monthEnd in monthEnds) {
      canvas.drawCircle(monthEnd.at, 2.6, fill);
    }
  }

  void _paintProjectSizeAboveMonthEnds(
    Canvas canvas,
    List<_MonthEndProjectSize> monthEnds,
  ) {
    for (final monthEnd in monthEnds) {
      final selected = emphasis.isSelected(monthEnd.month.month);
      final hovered = emphasis.isHovered(monthEnd.month.month);
      final label = TextPainter(
        text: TextSpan(
          text: monthEnd.projectSize.asCompactCount,
          style: TextStyle(
            color: selected || hovered ? EColors.textPrimary : EColors.textMuted,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(
          monthEnd.at.dx - label.width / 2,
          monthEnd.at.dy - 16,
        ),
      );
    }
  }
}

class const _MonthEndProjectSize({
  required final Offset at,
  required final LineAgeMonth month,
  required final int projectSize,
});
