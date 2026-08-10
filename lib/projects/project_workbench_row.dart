import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../run/flutter_run_device.dart';
import '../run/local_run_controls.dart';
import '../run/local_run_state.dart';
import '../ui/workbench_action_accents.dart';
import '../ui/widgets/deploy_platform_controls.dart';
import 'deployable_project.dart';
import 'project_app_icon_tile.dart';

/// Row-only width policy for [ProjectWorkbenchRow] — not shared chrome tokens.
abstract final class _WorkbenchRowLayout {
  static const clusterWidth = 320.0;
  static const clusterGap = 10.0;
  static const compactClusterGap = 6.0;
  static const secondaryActionWidth = 140.0;
  static const secondaryActionIconOnlyWidth = 44.0;

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

/// One project in the workbench list: identity + Line age + platform Run/Deploy.
class ProjectWorkbenchRow extends StatelessWidget {
  const ProjectWorkbenchRow({
    super.key,
    required this.project,
    required this.platforms,
    required this.localRunState,
    required this.showLineAge,
    this.lineAgeSubtitle = '…',
    this.localRun,
    this.ongoingDeploy,
    this.waitingDeploys = const [],
    required this.onLineAge,
    required this.onDeploy,
    required this.onRun,
    required this.onStopRun,
    required this.onOpenOngoingDeploy,
  });

  final DeployableProject project;
  final List<DeployPlatform> platforms;
  final LocalRunState localRunState;
  final bool showLineAge;
  final String lineAgeSubtitle;
  final LocalRunControls? localRun;
  final DeployJob? ongoingDeploy;
  final List<DeployJob> waitingDeploys;
  final VoidCallback onLineAge;
  final ValueChanged<DeployPlatform> onDeploy;
  final ValueChanged<FlutterRunDevice> onRun;
  final VoidCallback onStopRun;
  final VoidCallback onOpenOngoingDeploy;

  /// Width at which identity / Line age / clusters sit at preferred maxima.
  /// Further width is unused blank inside the row (list padding is not included).
  static double saturatedWidth({
    required int platformCount,
    required bool showLineAge,
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
    final lineAge =
        showLineAge ? _WorkbenchRowLayout.secondaryActionWidth : 0.0;
    final platforms = math.max(0, platformCount);
    final clusters = platforms * _WorkbenchRowLayout.clusterWidth;
    final clusterGaps = math.max(0, platforms - 1) * clusterGap;
    final afterIdentityGap = platforms > 0 || lineAge > 0
        ? ELayout.spaceMd
        : 0.0;
    final lineAgeGap = lineAge > 0 ? clusterGap : 0.0;
    return rowPadH * 2 +
        identity +
        afterIdentityGap +
        lineAge +
        lineAgeGap +
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
      attention: project.hasChangedSources ||
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
          final widths = _rowWidths(
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
                  child: _identity(),
                ),
                const SizedBox(width: ELayout.spaceMd),
              ],
              if (widths.lineAge > 0) ...[
                SizedBox(
                  width: widths.lineAge,
                  child: widths.lineAge >=
                          _WorkbenchRowLayout.secondaryActionWidth
                      ? ETintedAction.compact(
                          accent: WorkbenchActionAccents.lineAge,
                          icon: Icons.bar_chart_rounded,
                          title: 'Line age',
                          subtitle: lineAgeSubtitle,
                          onActivated: onLineAge,
                        )
                      : ETintedAction.iconOnly(
                          accent: WorkbenchActionAccents.lineAge,
                          icon: Icons.bar_chart_rounded,
                          title: 'Line age',
                          subtitle: lineAgeSubtitle,
                          onActivated: onLineAge,
                        ),
                ),
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

  /// Identity first (up to max), then Line age, then clusters share the rest.
  /// Line age steps down full-width → icon-only → hidden rather than squeeze
  /// the identity column below [_WorkbenchRowLayout.identityMinWidth]; clusters
  /// never steal identity to satisfy a large minimum.
  ({double identity, double lineAge, double cluster}) _rowWidths(
    double maxWidth, {
    required bool compact,
    required double clusterGap,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return (identity: 0, lineAge: 0, cluster: 0);
    }

    final identityMax = compact
        ? _WorkbenchRowLayout.compactIdentityMaxWidth
        : _WorkbenchRowLayout.identityMaxWidth;

    if (platforms.isEmpty) {
      final lineAge = _lineAgeWidthLeavingIdentityFloor(
        budget: maxWidth,
        clusterGap: clusterGap,
      );
      final identity = (maxWidth - (lineAge > 0 ? lineAge + clusterGap : 0))
          .clamp(0.0, identityMax);
      return (identity: identity, lineAge: lineAge, cluster: 0);
    }

    final clusterGaps = math.max(0, platforms.length - 1) * clusterGap;
    final clusterFloorTotal =
        platforms.length * _WorkbenchRowLayout.clusterAbsoluteFloor;
    final afterIdentityGap = ELayout.spaceMd;

    // What identity may spend once clusters hold their floor.
    var identityBudget =
        maxWidth - clusterGaps - clusterFloorTotal - afterIdentityGap;
    final lineAge = _lineAgeWidthLeavingIdentityFloor(
      budget: identityBudget,
      clusterGap: clusterGap,
    );
    if (lineAge > 0) {
      identityBudget -= lineAge + clusterGap;
    }
    if (identityBudget <= 0) {
      return (
        identity: 0,
        lineAge: 0,
        cluster: ((maxWidth - clusterGaps) / platforms.length)
            .floorToDouble()
            .clamp(0.0, _WorkbenchRowLayout.clusterWidth),
      );
    }

    final identity = math.min(identityMax, identityBudget);
    // Floor cluster width so subpixel rounding cannot overflow the row.
    final cluster =
        (((clusterFloorTotal + identityBudget - identity) / platforms.length)
                .floorToDouble())
            .clamp(0.0, _WorkbenchRowLayout.clusterWidth);

    return (identity: identity, lineAge: lineAge, cluster: cluster);
  }

  /// Widest Line age tier (full labeled → icon-only → 0) whose gap-inclusive
  /// cost still leaves the identity floor inside [budget].
  double _lineAgeWidthLeavingIdentityFloor({
    required double budget,
    required double clusterGap,
  }) {
    if (!showLineAge) return 0;
    for (final tierWidth in const [
      _WorkbenchRowLayout.secondaryActionWidth,
      _WorkbenchRowLayout.secondaryActionIconOnlyWidth,
    ]) {
      if (budget - tierWidth - clusterGap >=
          _WorkbenchRowLayout.identityMinWidth) {
        return tierWidth;
      }
    }
    return 0;
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
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            project.name,
            style: EText.caption.copyWith(
              color: EColors.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
          ),
        ),
      ],
    );
  }

  Widget _platformCluster(DeployPlatform platform) {
    if (!project.supports(platform)) {
      return _unavailablePlatformCluster(platform);
    }

    final runDevice = _runDeviceFor(platform);
    final canRun = localRun != null && runDevice != null;
    final runStatus = canRun ? _activeRunStatus(runDevice) : null;
    final runHasException = canRun && _runHasException(runDevice);
    final idleSubtitle =
        platform == DeployPlatform.macos ? 'Debug' : 'Simulator';

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
            trailing: _runStopControl(runStatus),
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
    return Opacity(
      opacity: 0.42,
      child: IgnorePointer(
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
      ),
    );
  }

  Widget? _runStopControl(LocalRunStatus? runStatus) {
    if (runStatus != LocalRunStatus.starting &&
        runStatus != LocalRunStatus.running) {
      return null;
    }
    return Tooltip(
      message: 'Stop run',
      child: InkWell(
        onTap: onStopRun,
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
    if (localRunState.projectId != project.projectId) return null;
    if (localRunState.deviceKey != device.key) return null;
    if (!localRunState.status.isActive) return null;
    return localRunState.status;
  }

  bool _runHasException(FlutterRunDevice device) {
    if (localRunState.projectId != project.projectId) return false;
    if (localRunState.deviceKey != device.key) return false;
    if (!localRunState.status.isActive) return false;
    return localRunState.flutterException != null;
  }

  static FlutterRunDevice? _runDeviceFor(DeployPlatform platform) =>
      switch (platform) {
        DeployPlatform.macos => FlutterRunDevice.macos,
        DeployPlatform.ios => FlutterRunDevice.meSim,
      };
}
