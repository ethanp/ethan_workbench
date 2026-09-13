import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../run/flutter_run_device.dart';
import '../run/local_run_state.dart';
import '../commit/uncommitted_change_counts.dart';
import '../commit/uncommitted_file_diff.dart';
import '../ui/workbench_action_accents.dart';
import '../ui/widgets/deploy_platform_controls.dart';
import 'project_app_icon_tile.dart';
import 'workbench_project.dart';

/// Preferred maxima for identity, then Line age + commit, then clusters.
abstract final class _WorkbenchRowLayout() {
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
class const _WorkbenchRowSlotWidths({
  required final double identity,
  required final double lineAge,
  required final double commit,
  required final double cluster,
});

class const _SecondaryActionWidths({
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
        ? _WorkbenchRowLayout.compactRowPadH
        : _WorkbenchRowLayout.rowPadH;
    final clusterGap = compact
        ? _WorkbenchRowLayout.compactClusterGap
        : _WorkbenchRowLayout.clusterGap;
    final identity = compact
        ? _WorkbenchRowLayout.compactIdentityMaxWidth
        : _WorkbenchRowLayout.identityMaxWidth;
    final secondary = _SecondaryActionWidths(
      lineAge: showLineAge ? _WorkbenchRowLayout.lineAgeWidth : 0,
      commit: showCommit ? _WorkbenchRowLayout.commitWidth : 0,
    );
    final platforms = math.max(0, platformCount);
    final clusters = platforms * _WorkbenchRowLayout.clusterWidth;
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
        ? _WorkbenchRowLayout.compactClusterGap
        : _WorkbenchRowLayout.clusterGap;
    final rowPadH = compact
        ? _WorkbenchRowLayout.compactRowPadH
        : _WorkbenchRowLayout.rowPadH;
    return ESurface(
      kind: ESurfaceKind.row,
      attention:
          project.hasChangedSources ||
          macosRunStatus != null ||
          meSimRunStatus != null ||
          ongoingDeploy != null,
      padding: EdgeInsets.fromLTRB(
        rowPadH,
        _WorkbenchRowLayout.rowPadV,
        rowPadH,
        _WorkbenchRowLayout.rowPadV,
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
                SizedBox(width: widths.identity, child: _identity()),
                const SizedBox(width: ELayout.spaceMd),
              ],
              if (widths.lineAge > 0) ...[
                SizedBox(width: widths.lineAge, child: _lineAgeAction()),
                SizedBox(width: clusterGap),
              ],
              if (widths.commit > 0) ...[
                SizedBox(width: widths.commit, child: _commitAction()),
                SizedBox(width: clusterGap),
              ],
              for (var index = 0; index < platforms.length; index++) ...[
                if (index > 0) SizedBox(width: clusterGap),
                SizedBox(
                  width: widths.cluster,
                  child: _platformCluster(platforms[index]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Line age and commit hide rather than squeeze identity below
  /// [_WorkbenchRowLayout.identityMinWidth]; clusters never steal
  /// identity to satisfy a large minimum.
  _WorkbenchRowSlotWidths _slotWidths(
    double maxWidth, {
    required bool compact,
    required double clusterGap,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return const _WorkbenchRowSlotWidths(
        identity: 0,
        lineAge: 0,
        commit: 0,
        cluster: 0,
      );
    }

    final identityMax = compact
        ? _WorkbenchRowLayout.compactIdentityMaxWidth
        : _WorkbenchRowLayout.identityMaxWidth;

    if (platforms.isEmpty) {
      final secondary = _secondaryWidthsLeavingIdentityFloor(
        budget: maxWidth,
        clusterGap: clusterGap,
      );
      final identity =
          (maxWidth - secondary.occupiedWithTrailingGap(clusterGap))
              .clamp(0.0, identityMax);
      return _WorkbenchRowSlotWidths(
        identity: identity,
        lineAge: secondary.lineAge,
        commit: secondary.commit,
        cluster: 0,
      );
    }

    final clusterGaps = math.max(0, platforms.length - 1) * clusterGap;
    final clusterFloorTotal =
        platforms.length * _WorkbenchRowLayout.clusterAbsoluteFloor;
    final afterIdentityGap = ELayout.spaceMd;

    var identityBudget =
        maxWidth - clusterGaps - clusterFloorTotal - afterIdentityGap;
    final secondary = _secondaryWidthsLeavingIdentityFloor(
      budget: identityBudget,
      clusterGap: clusterGap,
    );
    identityBudget -= secondary.occupiedWithTrailingGap(clusterGap);
    if (identityBudget <= 0) {
      return _WorkbenchRowSlotWidths(
        identity: 0,
        lineAge: 0,
        commit: 0,
        cluster: ((maxWidth - clusterGaps) / platforms.length)
            .floorToDouble()
            .clamp(0.0, _WorkbenchRowLayout.clusterWidth),
      );
    }

    final identity = math.min(identityMax, identityBudget);
    final cluster =
        (((clusterFloorTotal + identityBudget - identity) / platforms.length)
                .floorToDouble())
            .clamp(0.0, _WorkbenchRowLayout.clusterWidth);

    return _WorkbenchRowSlotWidths(
      identity: identity,
      lineAge: secondary.lineAge,
      commit: secondary.commit,
      cluster: cluster,
    );
  }

  /// Line age + commit width when the pair still leaves the identity floor
  /// inside [budget]; otherwise both hidden.
  _SecondaryActionWidths _secondaryWidthsLeavingIdentityFloor({
    required double budget,
    required double clusterGap,
  }) {
    final wanted = _SecondaryActionWidths(
      lineAge: showLineAge ? _WorkbenchRowLayout.lineAgeWidth : 0,
      commit: showCommit ? _WorkbenchRowLayout.commitWidth : 0,
    );
    if (wanted.occupied(clusterGap) == 0) return wanted;
    if (budget - wanted.occupiedWithTrailingGap(clusterGap) >=
        _WorkbenchRowLayout.identityMinWidth) {
      return wanted;
    }
    return const _SecondaryActionWidths(lineAge: 0, commit: 0);
  }

  Widget _lineAgeAction() {
    return _WorkbenchIconCaptionAction(
      accent: WorkbenchActionAccents.lineAge,
      icon: Icons.bar_chart_rounded,
      tooltip: 'Line age · $lineAgeSubtitle',
      caption: Text(
        lineAgeSubtitle,
        style: EText.caption.copyWith(
          color: WorkbenchActionAccents.lineAge.withValues(alpha: 0.62),
          fontSize: ELayout.typeSize(12),
          height: 1.15,
        ),
        maxLines: 1,
      ),
      onActivated: onLineAge,
    );
  }

  Widget _commitAction() {
    final counts = uncommittedChanges;
    final caption = counts?.caption ?? '…';
    return _WorkbenchIconCaptionAction(
      accent: WorkbenchActionAccents.commit,
      icon: Icons.commit_rounded,
      tooltip: 'Commit · $caption',
      caption: _commitCaption(counts),
      onActivated: onCommit,
    );
  }

  Widget _commitCaption(UncommittedChangeCounts? counts) {
    final style = EText.caption.copyWith(
      fontSize: ELayout.typeSize(12),
      height: 1.15,
    );
    if (counts == null) {
      return Text(
        '…',
        style: style.copyWith(
          color: WorkbenchActionAccents.commit.withValues(alpha: 0.62),
        ),
        maxLines: 1,
      );
    }
    if (counts.isClean || !counts.hasLineEdits) {
      return Text(
        counts.caption,
        style: style.copyWith(
          color: WorkbenchActionAccents.commit.withValues(alpha: 0.62),
        ),
        maxLines: 1,
      );
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(
            text: '+${counts.added.asCompactCount}',
            style: TextStyle(color: DiffLineKind.insertion.foreground),
          ),
          TextSpan(
            text: ' / ',
            style: TextStyle(
              color: WorkbenchActionAccents.commit.withValues(alpha: 0.62),
            ),
          ),
          TextSpan(
            text: '-${counts.removed.asCompactCount}',
            style: TextStyle(color: DiffLineKind.deletion.foreground),
          ),
        ],
      ),
      maxLines: 1,
    );
  }

  Widget _identity() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProjectAppIconTile(
          iconPngBytes: project.iconPngBytes,
          size: ELayout.listRowIcon,
        ),
        const SizedBox(height: ELayout.spaceXs),
        Text(
          project.name,
          style: EText.caption.copyWith(
            color: EColors.textPrimary,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _platformCluster(DeployPlatform platform) {
    if (!project.supports(platform)) {
      return _unavailablePlatformCluster(platform);
    }

    final runDevice = _runDeviceFor(platform);
    final canRun = canRunLocally && runDevice != null;
    final runStatus = canRun ? _activeRunStatus(runDevice) : null;
    final runHasException = canRun && _runHasException(runDevice);
    final idleSubtitle = platform == DeployPlatform.macos
        ? 'Debug'
        : 'Simulator';

    return EActionCluster(
      accent: platform.accent,
      icon: platform.icon,
      label: platform.label,
      cells: [
        if (canRun)
          EActionClusterCell(
            icon: runStatus != null
                ? Icons.play_circle_filled_rounded
                : Icons.play_arrow_rounded,
            title: 'Run',
            subtitle: runStatus != null
                ? (runHasException
                      ? 'Exception'
                      : runStatus.subtitleGivenIdle(idleSubtitle))
                : idleSubtitle,
            condensedLabel: 'Run',
            statusLabel: runHasException ? 'exception' : runStatus?.chipLabel,
            statusTone: runHasException
                ? EStatusTone.danger
                : runStatus?.chipTone,
            live: runStatus != null,
            trailing: _runStopControl(runStatus, runDevice),
            onActivated: () => onRun(runDevice),
          ),
        deployActionCell(
          platform: platform,
          lastDeployedAt: project.lastDeployedAt[platform],
          sourceStatus: project.sourceStatusFor(platform),
          ongoingDeploy: ongoingDeploy,
          waitingDeploy: _waitingDeployFor(platform),
          onOpenOngoing: onOpenOngoingDeploy,
          onSelected: () => onDeploy(platform),
        ),
      ],
    );
  }

  Widget _unavailablePlatformCluster(DeployPlatform platform) {
    return IgnorePointer(
      child: EActionCluster(
        accent: EColors.textMuted,
        icon: platform.icon,
        label: platform.label,
        cells: [
          EActionClusterCell(
            icon: Icons.phonelink_off_rounded,
            title: 'Not available',
            subtitle: 'No ${platform.label} target',
            condensedLabel: 'N/A',
            onActivated: () {},
          ),
        ],
      ),
    );
  }

  Widget? _runStopControl(
    LocalRunStatus? runStatus,
    FlutterRunDevice runDevice,
  ) {
    if (runStatus != LocalRunStatus.starting &&
        runStatus != LocalRunStatus.running) {
      return null;
    }
    return Tooltip(
      message: 'Stop run',
      child: InkWell(
        onTap: () => onStopRun(runDevice),
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(
            Icons.stop_circle_rounded,
            size: 18,
            color: EColors.danger,
          ),
        ),
      ),
    );
  }

  DeployJob? _waitingDeployFor(DeployPlatform platform) {
    for (final job in waitingDeploys) {
      if (job.projectId == project.projectId && job.platform == platform) {
        return job;
      }
    }
    return null;
  }

  LocalRunStatus? _activeRunStatus(FlutterRunDevice device) {
    final runState = runStateFor(device);
    if (!runState.status.isActive) return null;
    return runState.status;
  }

  bool _runHasException(FlutterRunDevice device) {
    final runState = runStateFor(device);
    if (!runState.status.isActive) return false;
    return runState.flutterException != null;
  }

  static FlutterRunDevice? _runDeviceFor(DeployPlatform platform) =>
      switch (platform) {
        DeployPlatform.macos => FlutterRunDevice.macos,
        DeployPlatform.ios => FlutterRunDevice.meSim,
      };
}

class const _WorkbenchIconCaptionAction({
  required final Color accent,
  required final IconData icon,
  required final String tooltip,
  required final Widget caption,
  required final VoidCallback? onActivated,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ESurface(
        kind: ESurfaceKind.tinted,
        accent: accent,
        onActivated: onActivated,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: SizedBox(
          height: 44,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(height: 2),
              FittedBox(fit: BoxFit.scaleDown, child: caption),
            ],
          ),
        ),
      ),
    );
  }
}
