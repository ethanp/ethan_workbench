import 'package:ethan_ui/ethan_ui.dart';

/// Preferred maxima for identity, then Line age + commit, then clusters.
abstract final class WorkbenchRowLayout() {
  static const clusterWidth = 320.0;
  static const clusterGap = 10.0;
  static const compactClusterGap = 6.0;

  /// Icon above SLOC — sized for a compact count like `10.8k`, not a title.
  static double get lineAgeWidth =>
      (8.0 * 2 + 32.0 * ELayout.typeScale).ceilToDouble();

  /// Icon above `+104 / -502`.
  static double get commitWidth =>
      (8.0 * 2 + 76.0 * ELayout.typeScale).ceilToDouble();

  /// Icon-above-title column — sized for typical project names on 1–2 lines.
  static const identityMaxWidth = 140.0;
  static const compactIdentityMaxWidth = 112.0;

  /// Identity keeps at least this much before Line age may claim its width;
  /// the row must always say which app it is.
  static const identityMinWidth = 76.0;

  /// Clusters may shrink to this before identity is reduced further.
  static const clusterAbsoluteFloor = 72.0;

  static const rowPadH = 14.0;
  static const compactRowPadH = 8.0;
  static const rowPadV = 12.0;
}

/// Identity first (up to max), then Line age + commit, then clusters.
class const WorkbenchRowSlotWidths({
  required final double identity,
  required final double lineAge,
  required final double commit,
  required final double cluster,
});

class const WorkbenchSecondaryActionWidths({
  required final double lineAge,
  required final double commit,
}) {
  double occupied(double clusterGap) {
    var width = 0.0;
    if (lineAge > 0) width += lineAge;
    if (commit > 0) {
      if (width > 0) width += clusterGap;
      width += commit;
    }
    return width;
  }

  double occupiedWithTrailingGap(double clusterGap) {
    final inner = occupied(clusterGap);
    if (inner == 0) return 0;
    return inner + clusterGap;
  }
}
