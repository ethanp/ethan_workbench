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
    final clusterCount = math.max(0, platformCount);
    return rowPadH * 2 +
        WorkbenchRowSlotWidths(
          identity: compact
              ? WorkbenchRowLayout.compactIdentityMaxWidth
              : WorkbenchRowLayout.identityMaxWidth,
          lineAge: showLineAge ? WorkbenchRowLayout.lineAgeWidth : 0,
          commit: showCommit ? WorkbenchRowLayout.commitWidth : 0,
          cluster: clusterCount > 0 ? WorkbenchRowLayout.clusterWidth : 0,
        ).occupied(clusterGap: clusterGap, platformCount: clusterCount);
  }

  @override
  Widget build(BuildContext context) {
    final macosRunStatus = _activeRunStatus(FlutterRunDevice.macos);
    final meSimRunStatus = _activeRunStatus(FlutterRunDevice.meSim);
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
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
        builder: (context, constraints) => _actionRow(
          constraints.maxWidth,
          compact: compact,
        ),
      ),
    );
  }

  Widget _actionRow(double maxWidth, {required bool compact}) {
    final clusterGap = compact
        ? WorkbenchRowLayout.compactClusterGap
        : WorkbenchRowLayout.clusterGap;
    final widths = WorkbenchRowSlotWidths.allocate(
      maxWidth: maxWidth,
      platformCount: platforms.length,
      compact: compact,
      showLineAge: showLineAge,
      showCommit: showCommit,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: _actionRowChildren(widths, clusterGap: clusterGap),
    );
  }

  List<Widget> _actionRowChildren(
    WorkbenchRowSlotWidths widths, {
    required double clusterGap,
  }) {
    final children = <Widget>[];
    var slotIndex = 0;
    void addSlot(double width, Widget child) {
      if (width <= 0) return;
      final gap = WorkbenchRowSlotWidths.gapBeforeSlot(
        slotIndex: slotIndex,
        identityVisible: widths.identity > 0,
        clusterGap: clusterGap,
      );
      if (gap > 0) children.add(SizedBox(width: gap));
      children.add(SizedBox(width: width, child: child));
      slotIndex++;
    }

    addSlot(widths.identity, WorkbenchRowIdentity(project: project));
    addSlot(
      widths.lineAge,
      WorkbenchRowLineAgeAction(
        lineAgeSubtitle: lineAgeSubtitle,
        onLineAge: onLineAge,
      ),
    );
    addSlot(
      widths.commit,
      WorkbenchRowCommitAction(
        uncommittedChanges: uncommittedChanges,
        onCommit: onCommit,
      ),
    );
    for (final platform in platforms) {
      addSlot(
        widths.cluster,
        WorkbenchRowPlatformCluster(
          project: project,
          platform: platform,
          runStateFor: runStateFor,
          canRunLocally: canRunLocally,
          ongoingDeploy: ongoingDeploy,
          waitingDeploys: waitingDeploys,
          onDeploy: onDeploy,
          onRun: onRun,
          onStopRun: onStopRun,
          onOpenOngoingDeploy: onOpenOngoingDeploy,
        ),
      );
    }
    return children;
  }

  LocalRunStatus? _activeRunStatus(FlutterRunDevice device) {
    final runState = runStateFor(device);
    if (!runState.status.isActive) return null;
    return runState.status;
  }
}
