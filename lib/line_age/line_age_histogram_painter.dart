import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../ui/workbench_action_accents.dart';
import 'line_age_analyzer.dart';
import 'line_age_directory_groups.dart';
import 'line_age_histogram_geometry.dart';

/// Paints month totals stacked by directory with selection emphasis.
class LineAgeHistogramPainter extends CustomPainter {
  LineAgeHistogramPainter({
    required this.report,
    required this.legend,
    required this.hoveredMonth,
    required this.selectedMonth,
    required this.emphasizedDirectory,
  });

  final LineAgeReport report;
  final LineAgeDirectoryLegend legend;
  final String? hoveredMonth;
  final String? selectedMonth;
  final String? emphasizedDirectory;

  @override
  void paint(Canvas canvas, Size size) {
    if (report.months.isEmpty) return;
    final geometry = LineAgeHistogramGeometry(size);
    final dataMax = report.months
        .map((month) => month.totalLines)
        .reduce(math.max)
        .toDouble();
    final scale = NiceValueScale.forMax(dataMax);
    final monthCount = report.months.length;
    final width = geometry.bandWidth(monthCount);
    final gap = geometry.bandGap(monthCount, width);
    final originX = geometry.groupOriginX(monthCount, width, gap);

    _paintGrid(canvas, geometry, scale);
    _paintAxes(canvas, geometry, scale, width, gap, originX);
    _paintCaption(canvas, geometry);

    for (var monthIndex = 0; monthIndex < monthCount; monthIndex++) {
      final month = report.months[monthIndex];
      final x = originX + monthIndex * (width + gap);
      _paintMonthBar(
        canvas,
        geometry: geometry,
        month: month,
        x: x,
        width: width,
        scale: scale,
        isSelected: selectedMonth == month.month,
        isHovered: hoveredMonth == month.month,
      );
    }
  }

  void _paintMonthBar(
    Canvas canvas, {
    required LineAgeHistogramGeometry geometry,
    required LineAgeMonth month,
    required double x,
    required double width,
    required NiceValueScale scale,
    required bool isSelected,
    required bool isHovered,
  }) {
    final stacks = legend.stacksForMonth(month);
    if (stacks.isEmpty) return;

    final barTop = geometry.yForTotal(month.totalLines, scale.max);
    final barHeight =
        geometry.margin.top + geometry.innerHeight - barTop;
    if (barHeight < 0.5) return;

    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, barTop, width, barHeight),
      const Radius.circular(4),
    );

    canvas.save();
    canvas.clipRRect(barRect);

    var yBottom = geometry.margin.top + geometry.innerHeight;
    for (final stack in stacks) {
      final height = geometry.segmentHeight(stack.lineCount, scale.max);
      if (height < 0.5) {
        yBottom -= height;
        continue;
      }
      final yTop = yBottom - height;
      final isEmphasized = emphasizedDirectory == null ||
          emphasizedDirectory == stack.key;
      final monthDim = !isSelected && !isHovered && selectedMonth != null;
      var alpha = isEmphasized ? 0.92 : 0.18;
      if (monthDim) alpha *= 0.55;
      if (isHovered && isEmphasized) alpha = math.min(1.0, alpha + 0.06);
      canvas.drawRect(
        Rect.fromLTWH(x, yTop, width, height),
        Paint()..color = legend.colorForKey(stack.key).withValues(alpha: alpha),
      );
      if (height > 2.5 && isEmphasized) {
        canvas.drawLine(
          Offset(x, yTop),
          Offset(x + width, yTop),
          Paint()
            ..color = EColors.surface.withValues(alpha: 0.45)
            ..strokeWidth = 1,
        );
      }
      yBottom = yTop;
    }

    canvas.restore();

    if (isSelected) {
      canvas.drawRRect(
        barRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = WorkbenchActionAccents.lineAge.withValues(alpha: 0.95),
      );
    }

    final emphasized = isSelected || isHovered;
    final valueLabel = TextPainter(
      text: TextSpan(
        text: month.totalLines.asCompactCount,
        style: TextStyle(
          color: emphasized ? EColors.textPrimary : EColors.textMuted,
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    valueLabel.paint(
      canvas,
      Offset(x + width / 2 - valueLabel.width / 2, barTop - 16),
    );
  }

  void _paintGrid(
    Canvas canvas,
    LineAgeHistogramGeometry geometry,
    NiceValueScale scale,
  ) {
    final paint = Paint()
      ..color = EColors.border.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (final tick in scale.ticks) {
      if (tick == 0) continue;
      final y = geometry.yForTotal(tick, scale.max);
      canvas.drawLine(
        Offset(geometry.margin.left, y),
        Offset(geometry.margin.left + geometry.innerWidth, y),
        paint,
      );
    }
  }

  void _paintAxes(
    Canvas canvas,
    LineAgeHistogramGeometry geometry,
    NiceValueScale scale,
    double width,
    double gap,
    double originX,
  ) {
    final baselineY = geometry.margin.top + geometry.innerHeight;
    final axisPaint = Paint()
      ..color = EColors.borderStrong.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(geometry.margin.left, baselineY),
      Offset(geometry.margin.left + geometry.innerWidth, baselineY),
      axisPaint,
    );

    for (final tick in scale.ticks) {
      final y = geometry.yForTotal(tick, scale.max);
      final label = TextPainter(
        text: TextSpan(
          text: tick.round().asCompactCount,
          style: const TextStyle(color: EColors.textMuted, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(geometry.margin.left - label.width - 8, y - label.height / 2),
      );
    }

    for (var monthIndex = 0; monthIndex < report.months.length; monthIndex++) {
      final month = report.months[monthIndex].month;
      final x = originX + monthIndex * (width + gap);
      final isSelected = selectedMonth == month;
      final isHovered = hoveredMonth == month;
      final label = TextPainter(
        text: TextSpan(
          text: month,
          style: TextStyle(
            color: isSelected || isHovered
                ? EColors.textPrimary
                : EColors.textMuted,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(x + width / 2, baselineY + 10);
      canvas.rotate(-0.65);
      label.paint(canvas, Offset(-label.width / 2, 0));
      canvas.restore();
    }
  }

  void _paintCaption(Canvas canvas, LineAgeHistogramGeometry geometry) {
    final title = TextPainter(
      text: const TextSpan(
        text: 'Current lines by month · stacked by directory',
        style: TextStyle(
          color: EColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: geometry.innerWidth);
    title.paint(canvas, Offset(geometry.margin.left, 8));
  }

  @override
  bool shouldRepaint(covariant LineAgeHistogramPainter oldDelegate) =>
      oldDelegate.report != report ||
      oldDelegate.legend != legend ||
      oldDelegate.hoveredMonth != hoveredMonth ||
      oldDelegate.selectedMonth != selectedMonth ||
      oldDelegate.emphasizedDirectory != emphasizedDirectory;
}
