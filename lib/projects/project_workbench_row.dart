import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../run/flutter_run_device.dart';
import '../run/local_run_state.dart';
import '../ui/workbench_action_accents.dart';
import '../ui/widgets/deploy_platform_controls.dart';
import 'project_app_icon_tile.dart';
import 'workbench_project.dart';

/// Preferred maxima for identity, then Line age, then equal platform clusters.
abstract final class _IdentityLineAgeClusterWidths() {
  static const clusterWidth = 320.0;
  static const clusterGap = 10.0;
  static const compactClusterGap = 6.0;

  /// Icon above SLOC — sized for a compact count like `10.8k`, not a title.
  static double get lineAgeWidth =>
      (8.0 * 2 + 32.0 * ELayout.typeScale).ceilToDouble();

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

/// Identity first (up to max), then Line age, then clusters share the rest.
class const _IdentityThenLineAgeThenClusters({
  required final double identity,
  required final double lineAge,
  required final double cluster,
});

/// One project in the workbench list: identity + Line age + platform Run/Deploy.
class const ProjectWorkbenchRow({
  super.key,
  required final WorkbenchProject project,
  required final List<DeployPlatform> platforms,
  required final LocalRunState Function(FlutterRunDevice device) runStateFor,
  required final bool canRunLocally,
  required final bool showLineAge,
  final String lineAgeSubtitle = '…',
  final DeployJob? ongoingDeploy,
  final List<DeployJob> waitingDeploys = const [],
  required final VoidCallback onLineAge,
  required final ValueChanged<DeployPlatform> onDeploy,
  required final ValueChanged<FlutterRunDevice> onRun,
  required final ValueChanged<FlutterRunDevice> onStopRun,
  required final VoidCallback onOpenOngoingDeploy,
}) extends StatelessWidget {
  /// Width at which identity / Line age / clusters sit at preferred maxima.
  /// Further width is unused blank inside the row (list padding is not included).
  static double saturatedWidth({
    required int platformCount,
    required bool showLineAge,
    required bool compact,
  }) {
    final rowPadH = compact
        ? _IdentityLineAgeClusterWidths.compactRowPadH
        : _IdentityLineAgeClusterWidths.rowPadH;
    final clusterGap = compact
        ? _IdentityLineAgeClusterWidths.compactClusterGap
        : _IdentityLineAgeClusterWidths.clusterGap;
    final identity = compact
        ? _IdentityLineAgeClusterWidths.compactIdentityMaxWidth
        : _IdentityLineAgeClusterWidths.identityMaxWidth;
    final lineAge = showLineAge
        ? _IdentityLineAgeClusterWidths.lineAgeWidth
        : 0.0;
    final platforms = math.max(0, platformCount);
    final clusters = platforms * _IdentityLineAgeClusterWidths.clusterWidth;
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
        ? _IdentityLineAgeClusterWidths.compactClusterGap
        : _IdentityLineAgeClusterWidths.clusterGap;
    final rowPadH = compact
        ? _IdentityLineAgeClusterWidths.compactRowPadH
        : _IdentityLineAgeClusterWidths.rowPadH;
    return ESurface(
      kind: ESurfaceKind.row,
      attention:
          project.hasChangedSources ||
          macosRunStatus != null ||
          meSimRunStatus != null ||
          ongoingDeploy != null,
      padding: EdgeInsets.fromLTRB(
        rowPadH,
        _IdentityLineAgeClusterWidths.rowPadV,
        rowPadH,
        _IdentityLineAgeClusterWidths.rowPadV,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widths = _identityThenLineAgeThenClusterWidths(
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

  /// Line age hides rather than squeeze identity below
  /// [_IdentityLineAgeClusterWidths.identityMinWidth]; clusters never steal
  /// identity to satisfy a large minimum.
  _IdentityThenLineAgeThenClusters _identityThenLineAgeThenClusterWidths(
    double maxWidth, {
    required bool compact,
    required double clusterGap,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return const _IdentityThenLineAgeThenClusters(
        identity: 0,
        lineAge: 0,
        cluster: 0,
      );
    }

    final identityMax = compact
        ? _IdentityLineAgeClusterWidths.compactIdentityMaxWidth
        : _IdentityLineAgeClusterWidths.identityMaxWidth;

    if (platforms.isEmpty) {
      final lineAge = _lineAgeWidthLeavingIdentityFloor(
        budget: maxWidth,
        clusterGap: clusterGap,
      );
      final identity = (maxWidth - (lineAge > 0 ? lineAge + clusterGap : 0))
          .clamp(0.0, identityMax);
      return _IdentityThenLineAgeThenClusters(
        identity: identity,
        lineAge: lineAge,
        cluster: 0,
      );
    }

    final clusterGaps = math.max(0, platforms.length - 1) * clusterGap;
    final clusterFloorTotal =
        platforms.length * _IdentityLineAgeClusterWidths.clusterAbsoluteFloor;
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
      return _IdentityThenLineAgeThenClusters(
        identity: 0,
        lineAge: 0,
        cluster: ((maxWidth - clusterGaps) / platforms.length)
            .floorToDouble()
            .clamp(0.0, _IdentityLineAgeClusterWidths.clusterWidth),
      );
    }

    final identity = math.min(identityMax, identityBudget);
    // Floor cluster width so subpixel rounding cannot overflow the row.
    final cluster =
        (((clusterFloorTotal + identityBudget - identity) / platforms.length)
                .floorToDouble())
            .clamp(0.0, _IdentityLineAgeClusterWidths.clusterWidth);

    return _IdentityThenLineAgeThenClusters(
      identity: identity,
      lineAge: lineAge,
      cluster: cluster,
    );
  }

  /// Line age width when its gap-inclusive cost still leaves the identity
  /// floor inside [budget]; otherwise hidden.
  double _lineAgeWidthLeavingIdentityFloor({
    required double budget,
    required double clusterGap,
  }) {
    if (!showLineAge) return 0;
    final width = _IdentityLineAgeClusterWidths.lineAgeWidth;
    if (budget - width - clusterGap >=
        _IdentityLineAgeClusterWidths.identityMinWidth) {
      return width;
    }
    return 0;
  }

  Widget _lineAgeAction() {
    final accent = WorkbenchActionAccents.lineAge;
    return Tooltip(
      message: 'Line age · $lineAgeSubtitle',
      child: ESurface(
        kind: ESurfaceKind.tinted,
        accent: accent,
        onActivated: onLineAge,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: SizedBox(
          height: 44,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bar_chart_rounded, size: 16, color: accent),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  lineAgeSubtitle,
                  style: EText.caption.copyWith(
                    color: accent.withValues(alpha: 0.62),
                    fontSize: ELayout.typeSize(12),
                    height: 1.15,
                  ),
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
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
