import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_job.dart';
import '../deploy/deploy_queue_panel.dart';
import '../deploy/deploy_trigger.dart';
import '../deploy/job_screen.dart';
import '../run/local_run_controls.dart';
import '../run/local_run_key.dart';
import '../run/local_run_registry.dart';
import '../run/local_run_screen.dart';
import '../run/local_run_state.dart';
import '../run/local_run_switcher.dart';
import 'active_deploy_watch.dart';
import 'project_workbench_row.dart';

class const HomescreenPaneWidths({
  required final double deploy,
  required final double run,
});

/// Inline deploy/run rail selection and pane width math for the homescreen.
class HomescreenRailSelection({required final void Function() onChanged}) {
  static const queueOnlyWidth = 260.0;
  static const detailPaneMinWidth = 440.0;

  DeployJob? inlineJob;
  LocalRunControls? inlineRun;
  var runRailClosedByUser = false;

  bool showSideRail({
    required bool compact,
    required bool hasQueuePanelContent,
  }) {
    return !compact &&
        (hasQueuePanelContent || inlineJob != null || inlineRun != null);
  }

  double deployPaneMinWidth({required bool hasQueuePanelContent}) {
    if (!hasQueuePanelContent && inlineJob == null) return 0;
    return inlineJob != null ? detailPaneMinWidth : queueOnlyWidth;
  }

  double get runPaneMinWidth => inlineRun == null ? 0 : detailPaneMinWidth;

  HomescreenPaneWidths paneWidths({
    required double totalWidth,
    required bool compact,
    required int platformCount,
    required bool showLineAge,
    required bool showCommit,
    required bool hasQueuePanelContent,
  }) {
    final deployMin = deployPaneMinWidth(
      hasQueuePanelContent: hasQueuePanelContent,
    );
    final runMin = runPaneMinWidth;
    final listPadH = compact ? 6.0 : ELayout.spaceXl;
    final saturatedListWidth =
        listPadH * 2 +
        ProjectWorkbenchRow.saturatedWidth(
          platformCount: platformCount,
          showLineAge: showLineAge,
          showCommit: showCommit,
          compact: compact,
        );
    final surplus = math.max(
      0.0,
      totalWidth - saturatedListWidth - deployMin - runMin,
    );
    if (deployMin > 0 && runMin > 0) {
      return HomescreenPaneWidths(
        deploy: deployMin + surplus / 2,
        run: runMin + surplus / 2,
      );
    }
    if (deployMin > 0) {
      return HomescreenPaneWidths(deploy: deployMin + surplus, run: 0);
    }
    return HomescreenPaneWidths(deploy: 0, run: runMin + surplus);
  }

  void keepBuildLogOnNowJob(DeployJob? ongoing) {
    if (inlineJob == null) return;
    if (ongoing == null) return;
    if (ongoing.jobId == inlineJob!.jobId) return;
    inlineJob = ongoing;
  }

  void showJobInSideRail(DeployJob job) {
    inlineJob = job;
    onChanged();
  }

  void closeInlineJob() {
    inlineJob = null;
    onChanged();
  }

  void showRunInSideRail(LocalRunControls controls) {
    runRailClosedByUser = false;
    inlineRun = controls;
    onChanged();
  }

  void closeInlineRun() {
    runRailClosedByUser = true;
    inlineRun = null;
    onChanged();
  }

  void adoptRestoredActiveRunInRail(LocalRunRegistry? registry) {
    if (inlineRun != null || runRailClosedByUser) return;
    if (registry == null) return;
    for (final runState in registry.knownStates) {
      if (!runState.status.isActive) continue;
      final runKey = runState.runKey;
      if (runKey == null) continue;
      inlineRun = registry.controlsFor(runKey);
      return;
    }
  }

  List<LocalRunState> runPaneSessions(LocalRunRegistry? registry) {
    final active = [
      if (registry != null)
        for (final runState in registry.knownStates)
          if (runState.status.isActive) runState,
    ];
    final selected = inlineRun?.state;
    if (selected != null) {
      final selectedKey = selected.runKey;
      if (selectedKey != null &&
          !active.any((runState) => runState.runKey == selectedKey)) {
        return [selected, ...active];
      }
    }
    return active;
  }
}

class const HomescreenSideRails({
  required final Widget list,
  required final HomescreenPaneWidths paneWidths,
  required final Widget? deployPane,
  required final Widget? runPane,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: list),
        if (paneWidths.deploy > 0) deployPane!,
        if (paneWidths.run > 0) runPane!,
      ],
    );
  }
}

class const HomescreenDeployPane({
  required final double width,
  required final ActiveDeployWatch activeDeploy,
  required final DeployTrigger trigger,
  required final DeployJob? inlineJob,
  required final void Function(DeployJob job) onShowJob,
  required final VoidCallback onDismiss,
  required final VoidCallback onOpenOngoing,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DeployQueuePanel(
      ongoing: activeDeploy.ongoing,
      waiting: activeDeploy.waiting,
      restartAfterQueue: activeDeploy.restartAfterQueue,
      ongoingRemaining: activeDeploy.ongoingRemainingEstimate,
      width: width,
      detail: inlineJob == null
          ? null
          : DeployJobDetail(
              key: ValueKey<String>(inlineJob!.jobId),
              trigger: trigger,
              initialJob: inlineJob!,
              inSideRail: true,
              onDismiss: onDismiss,
              onRetryStarted: onShowJob,
            ),
      onOpenOngoing: onOpenOngoing,
      onCancelWaiting: (jobId) => activeDeploy.cancelWaiting(jobId),
      onReorderWaiting: activeDeploy.reorderWaiting,
    );
  }
}

class const HomescreenRunPane({
  required final double width,
  required final LocalRunControls inlineRun,
  required final List<LocalRunState> sessions,
  required final void Function(LocalRunKey runKey) onSessionSelected,
  required final VoidCallback onDismiss,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ESidePanel(
      title: 'Run',
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocalRunSwitcher(
            sessions: sessions,
            selectedRunKey: inlineRun.state.runKey,
            onSessionSelected: onSessionSelected,
            onDismiss: onDismiss,
          ),
          Expanded(
            child: LocalRunDetail(
              key: ObjectKey(inlineRun),
              session: inlineRun,
              inSideRail: true,
            ),
          ),
        ],
      ),
    );
  }
}
