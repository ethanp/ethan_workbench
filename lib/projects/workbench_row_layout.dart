import 'dart:math' as math;

import 'package:ethan_ui/theme/e_layout.dart';

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
}) {
  /// Gap before the visible slot at [slotIndex] (0 is the first visible slot).
  /// After identity the gap is [ELayout.spaceMd]; every later gap is [clusterGap].
  static double gapBeforeSlot({
    required int slotIndex,
    required bool identityVisible,
    required double clusterGap,
  }) {
    if (slotIndex <= 0) return 0;
    if (slotIndex == 1 && identityVisible) return ELayout.spaceMd;
    return clusterGap;
  }

  /// Line age and commit hide rather than squeeze identity below
  /// [WorkbenchRowLayout.identityMinWidth]; clusters never steal
  /// identity to satisfy a large minimum.
  factory allocate({
    required double maxWidth,
    required int platformCount,
    required bool compact,
    required bool showLineAge,
    required bool showCommit,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return const WorkbenchRowSlotWidths(
        identity: 0,
        lineAge: 0,
        commit: 0,
        cluster: 0,
      );
    }

    final clusterGap = compact
        ? WorkbenchRowLayout.compactClusterGap
        : WorkbenchRowLayout.clusterGap;
    final identityMax = compact
        ? WorkbenchRowLayout.compactIdentityMaxWidth
        : WorkbenchRowLayout.identityMaxWidth;
    final clusterCount = math.max(0, platformCount);
    final secondary = _secondaryActionsLeavingIdentityFloor(
      maxWidth: maxWidth,
      platformCount: clusterCount,
      clusterGap: clusterGap,
      wanted: WorkbenchSecondaryActionWidths(
        lineAge: showLineAge ? WorkbenchRowLayout.lineAgeWidth : 0,
        commit: showCommit ? WorkbenchRowLayout.commitWidth : 0,
      ),
    );
    final occupiedWithoutIdentity = WorkbenchRowSlotWidths(
      identity: 0,
      lineAge: secondary.lineAge,
      commit: secondary.commit,
      cluster: clusterCount > 0 ? WorkbenchRowLayout.clusterAbsoluteFloor : 0,
    ).occupied(clusterGap: clusterGap, platformCount: clusterCount);
    final identityBudget =
        maxWidth -
        occupiedWithoutIdentity -
        (occupiedWithoutIdentity > 0 ? ELayout.spaceMd : 0.0);
    if (identityBudget <= 0) {
      return _clustersSharingFullWidth(
        maxWidth: maxWidth,
        clusterCount: clusterCount,
        clusterGap: clusterGap,
      );
    }

    return _identityThenClusters(
      identityBudget: identityBudget,
      identityMax: identityMax,
      clusterCount: clusterCount,
      secondary: secondary,
    );
  }

  static WorkbenchRowSlotWidths _clustersSharingFullWidth({
    required double maxWidth,
    required int clusterCount,
    required double clusterGap,
  }) {
    final clusterGaps = math.max(0, clusterCount - 1) * clusterGap;
    return WorkbenchRowSlotWidths(
      identity: 0,
      lineAge: 0,
      commit: 0,
      cluster: clusterCount == 0
          ? 0.0
          : ((maxWidth - clusterGaps) / clusterCount)
              .floorToDouble()
              .clamp(0.0, WorkbenchRowLayout.clusterWidth),
    );
  }

  static WorkbenchRowSlotWidths _identityThenClusters({
    required double identityBudget,
    required double identityMax,
    required int clusterCount,
    required WorkbenchSecondaryActionWidths secondary,
  }) {
    final identity = math.min(identityMax, identityBudget);
    final identitySurplus = identityBudget - identity;
    final clusterFloorTotal =
        clusterCount * WorkbenchRowLayout.clusterAbsoluteFloor;
    return WorkbenchRowSlotWidths(
      identity: identity,
      lineAge: secondary.lineAge,
      commit: secondary.commit,
      cluster: clusterCount == 0
          ? 0.0
          : ((clusterFloorTotal + identitySurplus) / clusterCount)
              .floorToDouble()
              .clamp(0.0, WorkbenchRowLayout.clusterWidth),
    );
  }

  static WorkbenchSecondaryActionWidths _secondaryActionsLeavingIdentityFloor({
    required double maxWidth,
    required int platformCount,
    required double clusterGap,
    required WorkbenchSecondaryActionWidths wanted,
  }) {
    if (wanted.occupied(clusterGap) == 0) return wanted;
    final atIdentityFloor = WorkbenchRowSlotWidths(
      identity: WorkbenchRowLayout.identityMinWidth,
      lineAge: wanted.lineAge,
      commit: wanted.commit,
      cluster: platformCount > 0 ? WorkbenchRowLayout.clusterAbsoluteFloor : 0,
    );
    if (atIdentityFloor.occupied(
          clusterGap: clusterGap,
          platformCount: platformCount,
        ) <=
        maxWidth) {
      return wanted;
    }
    return const WorkbenchSecondaryActionWidths(lineAge: 0, commit: 0);
  }

  double occupied({
    required double clusterGap,
    required int platformCount,
  }) {
    var slotIndex = 0;
    var width = 0.0;
    void addSlot(double slotWidth) {
      if (slotWidth <= 0) return;
      width += gapBeforeSlot(
        slotIndex: slotIndex,
        identityVisible: identity > 0,
        clusterGap: clusterGap,
      );
      width += slotWidth;
      slotIndex++;
    }

    addSlot(identity);
    addSlot(lineAge);
    addSlot(commit);
    for (var index = 0; index < platformCount; index++) {
      addSlot(cluster);
    }
    return width;
  }
}

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
}
