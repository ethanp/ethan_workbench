import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'line_age_directory_groups.dart';
import 'line_age_histogram_scales.dart';
import 'line_age_report.dart';

/// Two time-aligned panes: project size above, last-touched bars below.
class LineAgeHistogramGeometry(final Size size) {
  static const leftGutter = 56.0;
  static const rightGutter = 16.0;
  static const bottomGutter = 72.0;
  static const topPad = 8.0;
  static const paneTitleHeight = 26.0;
  static const sizeMonthAxisHeight = 28.0;
  static const paneGap = 12.0;
  static const minVisibleBarHeight = 2.0;

  /// About 1in at 96 logical pixels per inch — both panes.
  static const oneInchYTickSpacing = 96.0;

  final EdgeInsets margin = const EdgeInsets.fromLTRB(
    leftGutter,
    topPad,
    rightGutter,
    bottomGutter,
  );

  final double innerWidth = math.max(0.0, size.width - leftGutter - rightGutter);

  double get _availablePlotHeight => math.max(
    0.0,
    size.height -
        topPad -
        paneTitleHeight * 2 -
        sizeMonthAxisHeight -
        paneGap -
        bottomGutter,
  );

  double get sizePlotHeight {
    if (_availablePlotHeight <= 0) return 0;
    return math.max(64.0, _availablePlotHeight * 0.32);
  }

  int tickCountAtOneInch(double plotHeight) =>
      math.max(2, (plotHeight / oneInchYTickSpacing).round());

  LineAgeHistogramScales scalesFor(LineAgeReport report) =>
      LineAgeHistogramScales.from(
        report,
        lastTouchedTickCount: tickCountAtOneInch(lastTouchedPlotHeight),
        projectSizeTickCount: tickCountAtOneInch(sizePlotHeight),
      );

  double get sizePlotTop => topPad + paneTitleHeight;

  Rect get sizePlot =>
      Rect.fromLTWH(leftGutter, sizePlotTop, innerWidth, sizePlotHeight);

  double get lastTouchedPlotTop =>
      sizePlotTop +
      sizePlotHeight +
      sizeMonthAxisHeight +
      paneGap +
      paneTitleHeight;

  double get lastTouchedPlotHeight =>
      math.max(0.0, size.height - bottomGutter - lastTouchedPlotTop);

  Rect get lastTouchedPlot => Rect.fromLTWH(
    leftGutter,
    lastTouchedPlotTop,
    innerWidth,
    lastTouchedPlotHeight,
  );

  double get sizePaneTitleY => topPad;

  double get lastTouchedPaneTitleY =>
      sizePlot.bottom + sizeMonthAxisHeight + paneGap;

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
    return leftGutter + math.max(0.0, (innerWidth - groupWidth) / 2);
  }

  LineAgeMonthColumns columnsFor(int monthCount) {
    final width = bandWidth(monthCount);
    final gap = bandGap(monthCount, width);
    return LineAgeMonthColumns(
      width: width,
      gap: gap,
      originX: groupOriginX(monthCount, width, gap),
    );
  }

  double heightInPlot(Rect plot, num value, double scaleMax) {
    if (scaleMax <= 0) return 0;
    return plot.height * (value / scaleMax);
  }

  double yInPlot(Rect plot, num value, double scaleMax) =>
      plot.bottom - heightInPlot(plot, value, scaleMax);

  double segmentHeight(num lineCount, double scaleMax) =>
      heightInPlot(lastTouchedPlot, lineCount, scaleMax);

  double visibleBarHeight(num totalLines, double scaleMax) {
    if (totalLines <= 0 || scaleMax <= 0) return 0;
    return math.max(minVisibleBarHeight, segmentHeight(totalLines, scaleMax));
  }

  double yForTotal(num totalLines, double scaleMax) =>
      yInPlot(lastTouchedPlot, totalLines, scaleMax);

  double yForVisibleBar(num totalLines, double scaleMax) =>
      lastTouchedPlot.bottom - visibleBarHeight(totalLines, scaleMax);

  /// Month column under [position]. Directory only when the pointer is on a stack.
  LineAgeStackHit? hitTestStack({
    required LineAgeReport report,
    required LineAgeDirectoryLegend legend,
    required Offset position,
  }) {
    if (report.timelineMonths.isEmpty) return null;
    final scale = scalesFor(report).lastTouched;
    final columns = columnsFor(report.timelineMonths.length);

    for (var monthIndex = 0; monthIndex < report.timelineMonths.length; monthIndex++) {
      final month = report.timelineMonths[monthIndex];
      final x = columns.leftAt(monthIndex);
      if (position.dx < x || position.dx > x + columns.width) continue;
      if (position.dy < sizePlot.top || position.dy > lastTouchedPlot.bottom) {
        continue;
      }
      if (!lastTouchedPlot.contains(position)) {
        return LineAgeStackHit(month: month, directory: null);
      }
      return _hitLastTouchedStack(
        month: month,
        legend: legend,
        position: position,
        scaleMax: scale.max,
      );
    }
    return null;
  }

  LineAgeStackHit _hitLastTouchedStack({
    required LineAgeMonth month,
    required LineAgeDirectoryLegend legend,
    required Offset position,
    required double scaleMax,
  }) {
    final stacks = legend.stacksForMonth(month);
    final barHeight = visibleBarHeight(month.totalLines, scaleMax);
    var yBottom = lastTouchedPlot.bottom;
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
}

/// Shared month-column layout for both panes.
class const LineAgeMonthColumns({
  required final double width,
  required final double gap,
  required final double originX,
}) {
  double leftAt(int monthIndex) => originX + monthIndex * (width + gap);

  double centerAt(int monthIndex) => leftAt(monthIndex) + width / 2;

  double rightAt(int monthIndex) => leftAt(monthIndex) + width;
}

/// Result of probing the histogram at a pointer position.
class const LineAgeStackHit({
  required final LineAgeMonth month,
  required final String? directory,
});
