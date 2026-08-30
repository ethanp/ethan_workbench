import 'dart:math' as math;

import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/painting.dart';

import 'line_age_analyzer.dart';
import 'line_age_directory_groups.dart';

/// Plot layout and stack hit-testing for the line-age histogram.
class LineAgeHistogramGeometry(final Size size) {
  this : margin = const EdgeInsets.fromLTRB(56, 36, 16, 72);

  final EdgeInsets margin;
  final double innerWidth = math.max(0.0, size.width - 72);
  final double innerHeight = math.max(0.0, size.height - 108);

  double bandWidth(int monthCount) {
    if (monthCount <= 0) return 0;
    return innerWidth / monthCount * 0.62;
  }

  double bandGap(int monthCount, double width) {
    if (monthCount <= 1) return 0;
    final leftover = innerWidth - width * monthCount;
    return math.max(leftover / monthCount, width * 0.35);
  }

  double groupOriginX(int monthCount, double width, double gap) {
    final groupWidth = monthCount * width + (monthCount - 1) * gap;
    return margin.left + math.max(0.0, (innerWidth - groupWidth) / 2);
  }

  static const minVisibleBarHeight = 2.0;

  double segmentHeight(num lineCount, double scaleMax) {
    if (scaleMax <= 0) return 0;
    return innerHeight * (lineCount / scaleMax);
  }

  /// Axis ticks stay on the true scale; bars with a few lines still get a sliver.
  double visibleBarHeight(num totalLines, double scaleMax) {
    if (totalLines <= 0 || scaleMax <= 0) return 0;
    return math.max(minVisibleBarHeight, segmentHeight(totalLines, scaleMax));
  }

  double yForTotal(num totalLines, double scaleMax) =>
      margin.top + innerHeight - segmentHeight(totalLines, scaleMax);

  double yForVisibleBar(num totalLines, double scaleMax) =>
      margin.top + innerHeight - visibleBarHeight(totalLines, scaleMax);

  /// Month column under [position], plus the directory stack segment if any.
  LineAgeStackHit? hitTestStack({
    required LineAgeReport report,
    required LineAgeDirectoryLegend legend,
    required Offset position,
  }) {
    if (report.timelineMonths.isEmpty) return null;
    final dataMax = report.timelineMonths
        .map((month) => month.totalLines)
        .reduce(math.max)
        .toDouble();
    final scale = NiceValueScale.forMax(dataMax);
    final monthCount = report.timelineMonths.length;
    final width = bandWidth(monthCount);
    final gap = bandGap(monthCount, width);
    final originX = groupOriginX(monthCount, width, gap);
    final plotBottom = margin.top + innerHeight;

    for (var monthIndex = 0; monthIndex < monthCount; monthIndex++) {
      final month = report.timelineMonths[monthIndex];
      final x = originX + monthIndex * (width + gap);
      if (position.dx < x || position.dx > x + width) continue;
      if (position.dy < margin.top || position.dy > plotBottom) continue;

      final stacks = legend.stacksForMonth(month);
      final barHeight = visibleBarHeight(month.totalLines, scale.max);
      var yBottom = plotBottom;
      for (final stack in stacks) {
        final height = month.totalLines == 0
            ? 0.0
            : barHeight * (stack.lineCount / month.totalLines);
        final yTop = yBottom - height;
        if (height >= 0.5 && position.dy >= yTop && position.dy <= yBottom) {
          return LineAgeStackHit(month: month, directory: stack.key);
        }
        yBottom = yTop;
      }

      return LineAgeStackHit(month: month, directory: null);
    }
    return null;
  }
}

/// Result of probing the histogram at a pointer position.
class const LineAgeStackHit({
  required final LineAgeMonth month,
  required final String? directory,
});
