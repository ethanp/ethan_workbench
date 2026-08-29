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
    if (report.timelineMonths.isEmpty) return;
    final geometry = LineAgeHistogramGeometry(size);
    final dataMax = report.timelineMonths
        .map((month) => month.totalLines)
        .reduce(math.max)
        .toDouble();
    final scale = NiceValueScale.forMax(dataMax);
    final monthCount = report.timelineMonths.length;
    final width = geometry.bandWidth(monthCount);
    final gap = geometry.bandGap(monthCount, width);
    final originX = geometry.groupOriginX(monthCount, width, gap);

    _paintGrid(canvas, geometry, scale);
    _paintAxes(canvas, geometry, scale, width, gap, originX);
    _paintCaption(canvas, geometry);

    for (var monthIndex = 0; monthIndex < monthCount; monthIndex++) {
      final month = report.timelineMonths[monthIndex];
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
    if (month.isEmpty) {
      _paintEmptySlot(canvas, geometry: geometry, x: x, width: width);
      return;
    }
    final stacks = legend.stacksForMonth(month);
    if (stacks.isEmpty) return;

    final barHeight = geometry.visibleBarHeight(month.totalLines, scale.max);
    if (barHeight <= 0) return;
    final barTop = geometry.yForVisibleBar(month.totalLines, scale.max);

    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, barTop, width, barHeight),
      const Radius.circular(4),
    );

    canvas.save();
    canvas.clipRRect(barRect);

    if (geometry.segmentHeight(month.totalLines, scale.max) <
        LineAgeHistogramGeometry.minVisibleBarHeight) {
      canvas.drawRect(
        Rect.fromLTWH(x, barTop, width, barHeight),
        Paint()
          ..color = legend
              .colorForKey(stacks.first.key)
              .withValues(alpha: _stackAlpha(
                isEmphasized: emphasizedDirectory == null ||
                    emphasizedDirectory == stacks.first.key,
                isSelected: isSelected,
                isHovered: isHovered,
              )),
      );
      canvas.restore();
      _paintBarChrome(
        canvas,
        barRect: barRect,
        barTop: barTop,
        x: x,
        width: width,
        month: month,
        isSelected: isSelected,
        isHovered: isHovered,
      );
      return;
    }

    var yBottom = geometry.margin.top + geometry.innerHeight;
    for (final stack in stacks) {
      final height = barHeight * (stack.lineCount / month.totalLines);
      if (height < 0.5) {
        yBottom -= height;
        continue;
      }
      final yTop = yBottom - height;
      final isEmphasized = emphasizedDirectory == null ||
          emphasizedDirectory == stack.key;
      canvas.drawRect(
        Rect.fromLTWH(x, yTop, width, height),
        Paint()
          ..color = legend.colorForKey(stack.key).withValues(
            alpha: _stackAlpha(
              isEmphasized: isEmphasized,
              isSelected: isSelected,
              isHovered: isHovered,
            ),
          ),
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
    _paintBarChrome(
      canvas,
      barRect: barRect,
      barTop: barTop,
      x: x,
      width: width,
      month: month,
      isSelected: isSelected,
      isHovered: isHovered,
    );
  }

  double _stackAlpha({
    required bool isEmphasized,
    required bool isSelected,
    required bool isHovered,
  }) {
    var alpha = isEmphasized ? 0.92 : 0.18;
    if (!isSelected && !isHovered && selectedMonth != null) alpha *= 0.55;
    if (isHovered && isEmphasized) alpha = math.min(1.0, alpha + 0.06);
    return alpha;
  }

  void _paintEmptySlot(
    Canvas canvas, {
    required LineAgeHistogramGeometry geometry,
    required double x,
    required double width,
  }) {
    const slotHeight = 3.0;
    final baselineY = geometry.margin.top + geometry.innerHeight;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, baselineY - slotHeight, width, slotHeight),
        const Radius.circular(2),
      ),
      Paint()..color = EColors.borderStrong.withValues(alpha: 0.28),
    );
  }

  void _paintBarChrome(
    Canvas canvas, {
    required RRect barRect,
    required double barTop,
    required double x,
    required double width,
    required LineAgeMonth month,
    required bool isSelected,
    required bool isHovered,
  }) {
    if (isSelected) {
      canvas.drawRRect(
        barRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = WorkbenchActionAccents.lineAge.withValues(alpha: 0.95),
      );
    }

    final valueLabel = TextPainter(
      text: TextSpan(
        text: month.totalLines.asCompactCount,
        style: TextStyle(
          color: isSelected || isHovered
              ? EColors.textPrimary
              : EColors.textMuted,
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
    _paintYTicks(canvas, geometry, scale);
    _paintYearDividers(canvas, geometry, width, gap, originX, baselineY);
    _paintMonthTicks(canvas, width, gap, originX, baselineY);
    _paintYearLabels(canvas, width, gap, originX, baselineY);
  }

  void _paintYTicks(
    Canvas canvas,
    LineAgeHistogramGeometry geometry,
    NiceValueScale scale,
  ) {
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
  }

  void _paintYearDividers(
    Canvas canvas,
    LineAgeHistogramGeometry geometry,
    double width,
    double gap,
    double originX,
    double baselineY,
  ) {
    final bands = report.yearBands;
    if (bands.length < 2) return;
    final paint = Paint()
      ..color = EColors.borderStrong.withValues(alpha: 0.42)
      ..strokeWidth = 1;
    for (var bandIndex = 1; bandIndex < bands.length; bandIndex++) {
      final previous = bands[bandIndex - 1];
      final next = bands[bandIndex];
      final previousRight =
          originX + previous.lastMonthIndex * (width + gap) + width;
      final nextLeft = originX + next.firstMonthIndex * (width + gap);
      final x = (previousRight + nextLeft) / 2;
      canvas.drawLine(
        Offset(x, geometry.margin.top),
        Offset(x, baselineY + 34),
        paint,
      );
    }
  }

  void _paintMonthTicks(
    Canvas canvas,
    double width,
    double gap,
    double originX,
    double baselineY,
  ) {
    for (var monthIndex = 0; monthIndex < report.timelineMonths.length; monthIndex++) {
      final month = report.timelineMonths[monthIndex];
      final x = originX + monthIndex * (width + gap);
      final isSelected = selectedMonth == month.month;
      final isHovered = hoveredMonth == month.month;
      final label = TextPainter(
        text: TextSpan(
          text: month.shortMonthName,
          style: TextStyle(
            color: isSelected || isHovered
                ? EColors.textPrimary
                : month.isEmpty
                    ? EColors.textMuted.withValues(alpha: 0.55)
                    : EColors.textMuted,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(x + width / 2, baselineY + 8);
      canvas.rotate(-0.65);
      label.paint(canvas, Offset(-label.width / 2, 0));
      canvas.restore();
    }
  }

  void _paintYearLabels(
    Canvas canvas,
    double width,
    double gap,
    double originX,
    double baselineY,
  ) {
    for (final band in report.yearBands) {
      final left = originX + band.firstMonthIndex * (width + gap);
      final right = originX + band.lastMonthIndex * (width + gap) + width;
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
