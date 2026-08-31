import 'dart:math' as math;

/// Hover, selection, and directory emphasis for the line-age chart.
class const LineAgeHistogramEmphasis({
  required final String? hoveredMonth,
  required final String? selectedMonth,
  required final String? emphasizedDirectory,
}) {
  bool isSelected(String yearMonth) => selectedMonth == yearMonth;

  bool isHovered(String yearMonth) => hoveredMonth == yearMonth;

  bool isEmphasized(String directoryKey) =>
      emphasizedDirectory == null || emphasizedDirectory == directoryKey;

  double opacityDimUnemphasizedAndUnselected({
    required bool directoryEmphasized,
    required String yearMonth,
  }) {
    var alpha = directoryEmphasized ? 0.92 : 0.18;
    if (!isSelected(yearMonth) && !isHovered(yearMonth) && selectedMonth != null) {
      alpha *= 0.55;
    }
    if (isHovered(yearMonth) && directoryEmphasized) {
      alpha = math.min(1.0, alpha + 0.06);
    }
    return alpha;
  }
}
