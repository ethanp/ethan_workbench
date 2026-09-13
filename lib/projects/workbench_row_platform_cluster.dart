import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../run/flutter_run_device.dart';
import '../run/local_run_state.dart';
import '../ui/widgets/deploy_platform_controls.dart';
import '../ui/widgets/e_action_cluster.dart';
import 'workbench_project.dart';

class const WorkbenchRowPlatformCluster({
  required final WorkbenchProject project,
  required final DeployPlatform platform,
  required final LocalRunState Function(FlutterRunDevice device) runStateFor,
  required final bool canRunLocally,
  required final DeployJob? ongoingDeploy,
  required final List<DeployJob> waitingDeploys,
  required final ValueChanged<DeployPlatform> onDeploy,
  required final ValueChanged<FlutterRunDevice> onRun,
  required final ValueChanged<FlutterRunDevice> onStopRun,
  required final VoidCallback onOpenOngoingDeploy,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (!project.supports(platform)) {
      return WorkbenchUnavailablePlatformCluster(platform: platform);
    }

    final runDevice = runDeviceFor(platform);
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
            trailing: WorkbenchRunStopControl.maybe(
              runStatus: runStatus,
              onStop: () => onStopRun(runDevice),
            ),
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

  static FlutterRunDevice? runDeviceFor(DeployPlatform platform) =>
      switch (platform) {
        DeployPlatform.macos => FlutterRunDevice.macos,
        DeployPlatform.ios => FlutterRunDevice.meSim,
      };
}

class const WorkbenchUnavailablePlatformCluster({
  required final DeployPlatform platform,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
}

class const WorkbenchRunStopControl({
  required final VoidCallback onStop,
}) extends StatelessWidget {
  static Widget? maybe({
    required LocalRunStatus? runStatus,
    required VoidCallback onStop,
  }) {
    if (runStatus != LocalRunStatus.starting &&
        runStatus != LocalRunStatus.running) {
      return null;
    }
    return WorkbenchRunStopControl(onStop: onStop);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Stop run',
      child: InkWell(
        onTap: onStop,
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
}
