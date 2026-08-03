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

  /// Icon-above-title column — sized for typical project names on 1–2 lines.
  static const identityMaxWidth = 140.0;
  static const compactIdentityMaxWidth = 112.0;

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
    this.localRun,
    this.ongoingDeploy,
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
  final LocalRunControls? localRun;
  final DeployJob? ongoingDeploy;
  final VoidCallback onLineAge;
  final ValueChanged<DeployPlatform> onDeploy;
  final ValueChanged<FlutterRunDevice> onRun;
  final VoidCallback onStopRun;
  final VoidCallback onOpenOngoingDeploy;

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
              if (showLineAge) ...[
                SizedBox(
                  width: _WorkbenchRowLayout.secondaryActionWidth,
                  child: ETintedAction.compact(
                    accent: WorkbenchActionAccents.lineAge,
                    icon: Icons.bar_chart_rounded,
                    title: 'Line age',
                    subtitle: 'Authorship',
                    onTap: onLineAge,
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

  /// Identity first (up to max); clusters share the rest equally.
  /// Never steals identity to satisfy a large cluster minimum — that zeroed the
  /// title column on phone when two platforms were present.
  ({double identity, double cluster}) _rowWidths(
    double maxWidth, {
    required bool compact,
    required double clusterGap,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return (identity: 0, cluster: 0);
    }

    final identityMax = compact
        ? _WorkbenchRowLayout.compactIdentityMaxWidth
        : _WorkbenchRowLayout.identityMaxWidth;
    final lineAgeBlock = showLineAge
        ? _WorkbenchRowLayout.secondaryActionWidth + clusterGap
        : 0.0;
    final clusterGaps = math.max(0, platforms.length - 1) * clusterGap;

    if (platforms.isEmpty) {
      final identity =
          (maxWidth - lineAgeBlock).clamp(0.0, identityMax);
      return (identity: identity, cluster: 0);
    }

    final afterIdentityGap = ELayout.spaceMd;
    final reservedWithoutIdentity =
        lineAgeBlock + clusterGaps + afterIdentityGap;
    final available = maxWidth - reservedWithoutIdentity;
    if (available <= 0) {
      return (identity: 0, cluster: 0);
    }

    final clusterFloorTotal =
        platforms.length * _WorkbenchRowLayout.clusterAbsoluteFloor;
    final identity = math.min(
      identityMax,
      math.max(0.0, available - clusterFloorTotal),
    );
    // Floor cluster width so subpixel rounding cannot overflow the row.
    final cluster = (((available - identity) / platforms.length).floorToDouble())
        .clamp(0.0, _WorkbenchRowLayout.clusterWidth);

    return (identity: identity, cluster: cluster);
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
            onTap: () => onRun(runDevice),
          ),
        deployActionCell(
          platform: platform,
          lastDeployedAt: project.lastDeployedAt[platform],
          sourceStatus: project.sourceStatusFor(platform),
          ongoingDeploy: ongoingDeploy,
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
              onTap: () {},
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
    return IconButton(
      tooltip: 'Stop run',
      onPressed: onStopRun,
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      style: IconButton.styleFrom(
        foregroundColor: EColors.danger,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.stop_circle_rounded),
    );
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

/// Banner above the project list while a deploy is in progress.
class OngoingDeployBanner extends StatelessWidget {
  const OngoingDeployBanner({
    super.key,
    required this.job,
    required this.onOpen,
    this.queuedCount = 0,
  });

  final DeployJob job;
  final VoidCallback onOpen;
  final int queuedCount;

  @override
  Widget build(BuildContext context) {
    final queueSuffix = queuedCount == 0
        ? ''
        : ' · +$queuedCount queued';
    return ETintedAction(
      accent: EColors.accentGlow,
      icon: Icons.rocket_launch_rounded,
      title: job.projectName,
      subtitle:
          '${job.platform.label} deploy in progress — tap to open$queueSuffix',
      chipLabel: job.status.pillLabel,
      chipTone: job.status.statusTone,
      onTap: onOpen,
    );
  }
}
