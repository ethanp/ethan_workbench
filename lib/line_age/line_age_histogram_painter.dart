import 'package:flutter/material.dart';

import 'last_touched_month_bars.dart';
import 'line_age_directory_groups.dart';
import 'line_age_histogram_emphasis.dart';
import 'line_age_histogram_geometry.dart';
import 'line_age_report.dart';
import 'line_age_selected_month_and_years.dart';
import 'project_size_pane.dart';

/// Composes project size, last-touched bars, and selected-month / years.
class LineAgeHistogramPainter({
  required final LineAgeReport report,
  required final LineAgeDirectoryLegend legend,
  required final String? hoveredMonth,
  required final String? selectedMonth,
  required final String? emphasizedDirectory,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (report.timelineMonths.isEmpty) return;
    final geometry = LineAgeHistogramGeometry(size);
    final scales = geometry.scalesFor(report);
    final columns = geometry.columnsFor(report.timelineMonths.length);
    final emphasis = LineAgeHistogramEmphasis(
      hoveredMonth: hoveredMonth,
      selectedMonth: selectedMonth,
      emphasizedDirectory: emphasizedDirectory,
    );
    LineAgeSelectedMonthAndYears(
      report: report,
      geometry: geometry,
      columns: columns,
      emphasis: emphasis,
    ).paint(canvas);
    ProjectSizePane(
      report: report,
      geometry: geometry,
      columns: columns,
      scale: scales.projectSize,
      emphasis: emphasis,
    ).paint(canvas);
    LastTouchedMonthBars(
      report: report,
      legend: legend,
      geometry: geometry,
      columns: columns,
      scale: scales.lastTouched,
      emphasis: emphasis,
    ).paint(canvas);
  }

  @override
  bool shouldRepaint(covariant LineAgeHistogramPainter oldDelegate) =>
      oldDelegate.report != report ||
      oldDelegate.legend != legend ||
      oldDelegate.hoveredMonth != hoveredMonth ||
      oldDelegate.selectedMonth != selectedMonth ||
      oldDelegate.emphasizedDirectory != emphasizedDirectory;
}
