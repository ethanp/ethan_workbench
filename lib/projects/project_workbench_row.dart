import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../run/flutter_run_device.dart';
import '../run/local_run_state.dart';
import '../commit/uncommitted_change_counts.dart';
import 'workbench_project.dart';
import 'workbench_row_identity.dart';
import 'workbench_row_layout.dart';
import 'workbench_row_platform_cluster.dart';

/// One project in the workbench list: identity + Line age + commit + Run/Deploy.
class const ProjectWorkbenchRow({
  super.key,
  required final WorkbenchProject project,
  required final List<DeployPlatform> platforms,
  required final LocalRunState Function(FlutterRunDevice device) runStateFor,
  required final bool canRunLocally,
  required final bool showLineAge,
  final String lineAgeSubtitle = '…',
  final bool showCommit = false,
  final UncommittedChangeCounts? uncommittedChanges,
  final DeployJob? ongoingDeploy,
  final List<DeployJob> waitingDeploys = const [],
  required final VoidCallback onLineAge,
  final VoidCallback? onCommit,
  required final ValueChanged<DeployPlatform> onDeploy,
  required final ValueChanged<FlutterRunDevice> onRun,
  required final ValueChanged<FlutterRunDevice> onStopRun,
  required final VoidCallback onOpenOngoingDeploy,
}) extends StatelessWidget {
  /// Width at which identity / Line age / commit / clusters sit at maxima.
  /// Further width is unused blank inside the row (list padding is not included).
  static double saturatedWidth({
    required int platformCount,
    required bool showLineAge,
    required bool showCommit,
    required bool compact,
  }) {
    final rowPadH = compact
        ? WorkbenchRowLayout.compactRowPadH
        : WorkbenchRowLayout.rowPadH;
    final clusterGap = compact
        ? WorkbenchRowLayout.compactClusterGap
        : WorkbenchRowLayout.clusterGap;
    final identity = compact
        ? WorkbenchRowLayout.compactIdentityMaxWidth
        : WorkbenchRowLayout.identityMaxWidth;
    final secondary = WorkbenchSecondaryActionWidths(
      lineAge: showLineAge ? WorkbenchRowLayout.lineAgeWidth : 0,
      commit: showCommit ? WorkbenchRowLayout.commitWidth : 0,
    );
    final platforms = math.max(0, platformCount);
    final clusters = platforms * WorkbenchRowLayout.clusterWidth;
    final clusterGaps = math.max(0, platforms - 1) * clusterGap;
    final afterIdentityGap =
        platforms > 0 || secondary.occupied(clusterGap) > 0
        ? ELayout.spaceMd
        : 0.0;
    return rowPadH * 2 +
        identity +
        afterIdentityGap +
        secondary.occupiedWithTrailingGap(clusterGap) +
        clusters +
        clusterGaps;
  }

  @override
  Widget build(BuildContext context) {
    final macosRunStatus = _activeRunStatus(FlutterRunDevice.macos);
    final meSimRunStatus = _activeRunStatus(FlutterRunDevice.meSim);
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    final clusterGap = compact
        ? WorkbenchRowLayout.compactClusterGap
        : WorkbenchRowLayout.clusterGap;
    final rowPadH = compact
        ? WorkbenchRowLayout.compactRowPadH
        : WorkbenchRowLayout.rowPadH;
    return ESurface(
      kind: ESurfaceKind.row,
      attention:
          project.hasChangedSources ||
          macosRunStatus != null ||
          meSimRunStatus != null ||
          ongoingDeploy != null,
      padding: EdgeInsets.fromLTRB(
        rowPadH,
        WorkbenchRowLayout.rowPadV,
        rowPadH,
        WorkbenchRowLayout.rowPadV,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widths = _slotWidths(
            constraints.maxWidth,
            compact: compact,
            clusterGap: clusterGap,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widths.identity > 0) ...[
                SizedBox(
                  width: widths.identity,
                  child: WorkbenchRowIdentity(project: project),
                ),
                const SizedBox(width: ELayout.spaceMd),
              ],
              if (widths.lineAge > 0) ...[
                SizedBox(
                  width: widths.lineAge,
                  child: WorkbenchRowLineAgeAction(
                    lineAgeSubtitle: lineAgeSubtitle,
                    onLineAge: onLineAge,
                  ),
                ),
                SizedBox(width: clusterGap),
              ],
              if (widths.commit > 0) ...[
                SizedBox(
                  width: widths.commit,
                  child: WorkbenchRowCommitAction(
                    uncommittedChanges: uncommittedChanges,
                    onCommit: onCommit,
                  ),
                ),
                SizedBox(width: clusterGap),
              ],
              for (var index = 0; index < platforms.length; index++) ...[
                if (index > 0) SizedBox(width: clusterGap),
                SizedBox(
                  width: widths.cluster,
                  child: WorkbenchRowPlatformCluster(
                    project: project,
                    platform: platforms[index],
                    runStateFor: runStateFor,
                    canRunLocally: canRunLocally,
                    ongoingDeploy: ongoingDeploy,
                    waitingDeploys: waitingDeploys,
                    onDeploy: onDeploy,
                    onRun: onRun,
                    onStopRun: onStopRun,
                    onOpenOngoingDeploy: onOpenOngoingDeploy,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Line age and commit hide rather than squeeze identity below
  /// [WorkbenchRowLayout.identityMinWidth]; clusters never steal
  /// identity to satisfy a large minimum.
  WorkbenchRowSlotWidths _slotWidths(
    double maxWidth, {
    required bool compact,
    required double clusterGap,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return const WorkbenchRowSlotWidths(
        identity: 0,
        lineAge: 0,
        commit: 0,
        cluster: 0,
      );
    }

    final identityMax = compact
        ? WorkbenchRowLayout.compactIdentityMaxWidth
        : WorkbenchRowLayout.identityMaxWidth;

    if (platforms.isEmpty) {
      final secondary = _secondaryWidthsLeavingIdentityFloor(
        budget: maxWidth,
        clusterGap: clusterGap,
      );
      final identity =
          (maxWidth - secondary.occupiedWithTrailingGap(clusterGap))
              .clamp(0.0, identityMax);
      return WorkbenchRowSlotWidths(
        identity: identity,
        lineAge: secondary.lineAge,
        commit: secondary.commit,
        cluster: 0,
      );
    }

    final clusterGaps = math.max(0, platforms.length - 1) * clusterGap;
    final clusterFloorTotal =
        platforms.length * WorkbenchRowLayout.clusterAbsoluteFloor;
    final afterIdentityGap = ELayout.spaceMd;

    var identityBudget =
        maxWidth - clusterGaps - clusterFloorTotal - afterIdentityGap;
    final secondary = _secondaryWidthsLeavingIdentityFloor(
      budget: identityBudget,
      clusterGap: clusterGap,
    );
    identityBudget -= secondary.occupiedWithTrailingGap(clusterGap);
    if (identityBudget <= 0) {
      return WorkbenchRowSlotWidths(
        identity: 0,
        lineAge: 0,
        commit: 0,
        cluster: ((maxWidth - clusterGaps) / platforms.length)
            .floorToDouble()
            .clamp(0.0, WorkbenchRowLayout.clusterWidth),
      );
    }

    final identity = math.min(identityMax, identityBudget);
    final cluster =
        (((clusterFloorTotal + identityBudget - identity) / platforms.length)
                .floorToDouble())
            .clamp(0.0, WorkbenchRowLayout.clusterWidth);

    return WorkbenchRowSlotWidths(
      identity: identity,
      lineAge: secondary.lineAge,
      commit: secondary.commit,
      cluster: cluster,
    );
  }

  /// Line age + commit width when the pair still leaves the identity floor
  /// inside [budget]; otherwise both hidden.
  WorkbenchSecondaryActionWidths _secondaryWidthsLeavingIdentityFloor({
    required double budget,
    required double clusterGap,
  }) {
    final wanted = WorkbenchSecondaryActionWidths(
      lineAge: showLineAge ? WorkbenchRowLayout.lineAgeWidth : 0,
      commit: showCommit ? WorkbenchRowLayout.commitWidth : 0,
    );
    if (wanted.occupied(clusterGap) == 0) return wanted;
    if (budget - wanted.occupiedWithTrailingGap(clusterGap) >=
        WorkbenchRowLayout.identityMinWidth) {
      return wanted;
    }
    return const WorkbenchSecondaryActionWidths(lineAge: 0, commit: 0);
  }

  LocalRunStatus? _activeRunStatus(FlutterRunDevice device) {
    final runState = runStateFor(device);
    if (!runState.status.isActive) return null;
    return runState.status;
  }
}
