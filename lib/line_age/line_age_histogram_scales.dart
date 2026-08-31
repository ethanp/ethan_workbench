import 'dart:math' as math;

import 'package:ethan_utils/ethan_utils.dart';

import 'line_age_report.dart';

/// Left axis is last-touched peak; right axis is project-size peak.
class LineAgeHistogramScales({
  required final NiceValueScale lastTouched,
  required final NiceValueScale projectSize,
}) {
  factory from(
    LineAgeReport report, {
    required int lastTouchedTickCount,
    required int projectSizeTickCount,
  }) {
    return LineAgeHistogramScales(
      lastTouched: NiceValueScale.forMax(
        _lastTouchedPeak(report),
        targetTickCount: lastTouchedTickCount,
      ),
      projectSize: NiceValueScale.forMax(
        report.projectSizeByMonth.peak.toDouble(),
        targetTickCount: projectSizeTickCount,
      ),
    );
  }

  static double _lastTouchedPeak(LineAgeReport report) {
    if (report.timelineMonths.isEmpty) return 0;
    return report.timelineMonths
        .map((month) => month.totalLines)
        .reduce(math.max)
        .toDouble();
  }
}
