import 'dart:async';
import 'dart:math' as math;

import 'package:ethan_utils/ethan_utils.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../app_identity.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_queue_panel.dart';
import '../deploy/deploy_trigger.dart';
import '../deploy/job_screen.dart';
import '../line_age/flutter_git_repos.dart';
import '../line_age/flutter_line_age.dart';
import '../line_age/line_age_analyzer.dart';
import '../line_age/line_age_cache.dart';
import '../line_age/line_age_screen.dart';
import '../ui/workbench_action_accents.dart';
import '../run/flutter_run_device.dart';
import '../run/local_run_controls.dart';
import '../run/local_run_key.dart';
import '../run/local_run_registry.dart';
import '../run/local_run_screen.dart';
import '../run/local_run_state.dart';
import 'active_deploy_watch.dart';
import 'project_deploy_flow.dart';
import 'project_local_run_flow.dart';
import 'project_workbench_row.dart';
import 'projects_catalog.dart';
import 'source_changes_progress.dart';
import 'workbench_project.dart';

class const ProjectsScreen({
  required final DeployTrigger trigger,
  final LocalRunRegistry? localRunRegistry,
}) extends StatefulWidget {
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState() extends State<ProjectsScreen> {
  late final ProjectsCatalog _catalog;
  late final ActiveDeployWatch _activeDeploy;
  late final ProjectDeployFlow _deployFlow;
  late final ProjectLocalRunFlow _localRunFlow;

  Timer? _sourceChangesRefreshTimer;
  StreamSubscription<void>? _localRunSubscription;

  /// Job shown in the deploy pane under the queue (null = not selected).
  DeployJob? _inlineJob;

  /// Run shown in the right-hand run pane (null = not selected).
  LocalRunControls? _inlineRun;

  /// After the user closes the run pane, do not auto-reopen until they tap Run.
  var _runRailClosedByUser = false;

  static const _queueOnlyWidth = 260.0;
  static const _detailPaneMinWidth = 440.0;

  @override
  void initState() {
    super.initState();
    _catalog = ProjectsCatalog(
      trigger: widget.trigger,
      onCatalogChanged: () {
        if (mounted) setState(() {});
      },
    );
    _activeDeploy = ActiveDeployWatch(
      trigger: widget.trigger,
      onActiveDeployChanged: () {
        if (!mounted) return;
        setState(_keepBuildLogOnNowJob);
      },
      onDeployFinished: _refreshAfterDeployFinished,
    );
    _deployFlow = ProjectDeployFlow(
      trigger: widget.trigger,
      activeDeploy: _activeDeploy,
      showJobInSideRailOrJobScreen: _showJobInSideRailOrJobScreen,
    );
    _localRunFlow = ProjectLocalRunFlow(
      showRunInSideRailOrRunScreen: _showRunInSideRailOrRunScreen,
    );

    _sourceChangesRefreshTimer = Timer.periodic(const Duration(seconds: 30), (
      _,
    ) {
      if (!mounted || _catalog.loading || _catalog.evaluatingChanges) return;
      unawaited(_reload(evaluateChanges: true, analyzeLineAgeAfterLoad: false));
    });

    final localRunRegistry = widget.localRunRegistry;
    if (localRunRegistry != null) {
      _adoptRestoredActiveRunInRail();
      _localRunSubscription = localRunRegistry.changes.listen((_) {
        if (!mounted) return;
        setState(_adoptRestoredActiveRunInRail);
      });
    }

    _activeDeploy.start();
    unawaited(_loadPersistedLineAgeCache());
    unawaited(_reload(evaluateChanges: true));
  }

  Future<void> _loadPersistedLineAgeCache() async {
    await LineAgeCache.instance.ensureLoaded();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sourceChangesRefreshTimer?.cancel();
    unawaited(_localRunSubscription?.cancel());
    unawaited(_activeDeploy.dispose());
    _catalog.dispose();
    super.dispose();
  }

  Future<void> _reload({
    required bool evaluateChanges,
    bool analyzeLineAgeAfterLoad = true,
  }) async {
    final outcome = await _catalog.load(evaluateChanges: evaluateChanges);
    if (!mounted) return;
    if (outcome == ProjectsCatalogLoadOutcome.unauthorized) {
      await widget.trigger.onUnauthorized?.call();
      return;
    }
    if (outcome == ProjectsCatalogLoadOutcome.failed &&
        evaluateChanges &&
        _catalog.hasProjects) {
      final message = _catalog.lastFailureMessage;
      if (message != null) {
        context.textSnackBar(message);
      }
    }
    setState(() {});
    if (analyzeLineAgeAfterLoad &&
        outcome == ProjectsCatalogLoadOutcome.succeeded &&
        widget.trigger.showLineAgeAnalysis) {
      unawaited(_blameDistinctGitRootsAfterRefresh());
    }
  }

  Future<void> _blameDistinctGitRootsAfterRefresh() async {
    final analyzePaths = FlutterGitRepos(
      flutterRoots: widget.trigger.flutterRoots,
    ).gitRoots;
    await Future.wait(analyzePaths.map(_analyzeOrCachedOneGitRoot));
    if (mounted) setState(() {});
  }

  Future<void> _analyzeOrCachedOneGitRoot(String repoPath) async {
    try {
      await LineAgeCache.instance.analyzeOrCached(repoPath);
    } catch (_) {
      // Keep other projects blaming; Line age subtitle stays "…" on failure.
    }
  }

  Future<void> _afterJobScreenClosed() async {
    await _activeDeploy.refresh();
    await _reload(evaluateChanges: true);
  }

  void _refreshAfterDeployFinished(DeployJob job) {
    if (!mounted) return;
    if (job.status != DeployJobStatus.succeeded) return;
    _catalog.markPlatformCurrentAfterDeploy(job);
    unawaited(_reload(evaluateChanges: true));
  }

  void _showJobInSideRailOrJobScreen(DeployJob job) {
    if (!mounted) return;
    // Phone / compact still uses the full-screen route.
    if (MediaQuery.sizeOf(context).shortestSide < 600) {
      unawaited(_pushJobScreen(job));
      return;
    }
    setState(() => _inlineJob = job);
  }

  void _keepBuildLogOnNowJob() {
    if (_inlineJob == null) return;
    final ongoing = _activeDeploy.ongoing;
    if (ongoing == null) return;
    if (ongoing.jobId == _inlineJob!.jobId) return;
    _inlineJob = ongoing;
  }

  Future<void> _pushJobScreen(DeployJob job) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            JobScreen(trigger: widget.trigger, initialJob: job),
      ),
    );
    await _afterJobScreenClosed();
  }

  void _closeInlineJob() {
    setState(() => _inlineJob = null);
    unawaited(_afterJobScreenClosed());
  }

  void _showRunInSideRailOrRunScreen(LocalRunControls controls) {
    if (!mounted) return;
    if (MediaQuery.sizeOf(context).shortestSide < 600) {
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => LocalRunScreen(session: controls),
          ),
        ),
      );
      return;
    }
    setState(() {
      _runRailClosedByUser = false;
      _inlineRun = controls;
    });
  }

  void _closeInlineRun() {
    setState(() {
      _runRailClosedByUser = true;
      _inlineRun = null;
    });
  }

  void _adoptRestoredActiveRunInRail() {
    if (_inlineRun != null || _runRailClosedByUser) return;
    final registry = widget.localRunRegistry;
    if (registry == null) return;
    for (final runState in registry.knownStates) {
      if (!runState.status.isActive) continue;
      final runKey = runState.runKey;
      if (runKey == null) continue;
      _inlineRun = registry.controlsFor(runKey);
      return;
    }
  }

  Future<void> _showOngoingJobScreen() async {
    final job = _activeDeploy.ongoing;
    if (job == null) return;
    await _deployFlow.showJobScreen(
      context,
      job,
      afterJobScreenClosed: _afterJobScreenClosed,
    );
  }

  Future<void> _deploy(WorkbenchProject project, DeployPlatform platform) {
    return _deployFlow.confirmAndStart(
      context,
      project: project,
      platform: platform,
      afterJobScreenClosed: _afterJobScreenClosed,
    );
  }

  Future<void> _run(WorkbenchProject project, FlutterRunDevice device) async {
    final registry = widget.localRunRegistry;
    if (registry == null) return;
    await _localRunFlow.startOrShowLocalRun(
      context,
      registry: registry,
      project: project,
      device: device,
    );
  }

  Future<void> _stopRun(
    WorkbenchProject project,
    FlutterRunDevice device,
  ) async {
    final registry = widget.localRunRegistry;
    if (registry == null) return;
    await _localRunFlow.stop(
      context,
      registry: registry,
      project: project,
      device: device,
    );
  }

  void _showFlutterLineAgeScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LineAgeScreen.flutterFleet(
          flutterRoots: widget.trigger.flutterRoots,
        ),
      ),
    );
  }

  Widget _flutterLineAgeAction() {
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    final subtitle = FlutterLineAge(flutterRoots: widget.trigger.flutterRoots)
        .cachedSlocSubtitle();
    if (compact) {
      return IconButton(
        tooltip: 'Line age · $subtitle',
        onPressed: _showFlutterLineAgeScreen,
        icon: const Icon(Icons.bar_chart_rounded),
      );
    }
    return SizedBox(
      width: 140,
      child: ETintedAction.compact(
        accent: WorkbenchActionAccents.lineAge,
        icon: Icons.bar_chart_rounded,
        title: 'Line age',
        subtitle: subtitle,
        onActivated: _showFlutterLineAgeScreen,
      ),
    );
  }

  void _showLineAgeScreen(WorkbenchProject project) {
    final gitRoot = LineAgeAnalyzer.findGitRoot(project.path) ?? project.path;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LineAgeScreen.repo(
          repoPath: project.path,
          repoName: path.basename(gitRoot),
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    await widget.trigger.onSignOut?.call();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    final showSideRail =
        !compact &&
        (_activeDeploy.hasQueuePanelContent ||
            _inlineJob != null ||
            _inlineRun != null);

    return EScaffoldShell(
      contentMaxWidth: showSideRail ? double.infinity : ELayout.contentMaxWidth,
      appBar: EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: widget.trigger.title,
        actions: [
          if (widget.trigger.showLineAgeAnalysis) _flutterLineAgeAction(),
          _checkForChangesAction(),
          if (widget.trigger.showSignOut)
            IconButton(
              tooltip: 'Sign out',
              onPressed: () => unawaited(_signOut()),
              icon: const Icon(Icons.logout_rounded),
            ),
        ],
      ),
      body: showSideRail ? _bodyWithSideRail(compact: compact) : _body(),
    );
  }

  /// Project list + deploy pane + run pane. Surplus past saturated rows
  /// is split across the visible panes.
  Widget _bodyWithSideRail({required bool compact}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paneWidths = _homescreenPaneWidths(
          totalWidth: constraints.maxWidth,
          compact: compact,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _body()),
            if (paneWidths.deploy > 0) _deployPane(width: paneWidths.deploy),
            if (paneWidths.run > 0) _runPane(width: paneWidths.run),
          ],
        );
      },
    );
  }

  Widget _deployPane({required double width}) {
    final inlineJob = _inlineJob;
    return DeployQueuePanel(
      ongoing: _activeDeploy.ongoing,
      waiting: _activeDeploy.waiting,
      ongoingRemaining: _activeDeploy.ongoingRemainingEstimate,
      width: width,
      detail: inlineJob == null
          ? null
          : DeployJobDetail(
              key: ValueKey<String>(inlineJob.jobId),
              trigger: widget.trigger,
              initialJob: inlineJob,
              inSideRail: true,
              onDismiss: _closeInlineJob,
              onRetryStarted: _showJobInSideRailOrJobScreen,
            ),
      onOpenOngoing: () => unawaited(_showOngoingJobScreen()),
      onCancelWaiting: (jobId) => _activeDeploy.cancelWaiting(jobId),
    );
  }

  Widget _runPane({required double width}) {
    final inlineRun = _inlineRun!;
    return ESidePanel(
      title: 'Run',
      width: width,
      child: LocalRunDetail(
        key: ObjectKey(inlineRun),
        session: inlineRun,
        inSideRail: true,
        onDismiss: _closeInlineRun,
      ),
    );
  }

  double get _deployPaneMinWidth {
    if (!_activeDeploy.hasQueuePanelContent && _inlineJob == null) return 0;
    return _inlineJob != null ? _detailPaneMinWidth : _queueOnlyWidth;
  }

  double get _runPaneMinWidth =>
      _inlineRun == null ? 0 : _detailPaneMinWidth;

  _HomescreenPaneWidths _homescreenPaneWidths({
    required double totalWidth,
    required bool compact,
  }) {
    final deployMin = _deployPaneMinWidth;
    final runMin = _runPaneMinWidth;
    final listPadH = compact ? 6.0 : ELayout.spaceXl;
    final saturatedListWidth =
        listPadH * 2 +
        ProjectWorkbenchRow.saturatedWidth(
          platformCount: widget.trigger.preferredPlatforms.length,
          showLineAge: widget.trigger.showLineAgeAnalysis,
          compact: compact,
        );
    final surplus = math.max(
      0.0,
      totalWidth - saturatedListWidth - deployMin - runMin,
    );
    if (deployMin > 0 && runMin > 0) {
      return _HomescreenPaneWidths(
        deploy: deployMin + surplus / 2,
        run: runMin + surplus / 2,
      );
    }
    if (deployMin > 0) {
      return _HomescreenPaneWidths(deploy: deployMin + surplus, run: 0);
    }
    return _HomescreenPaneWidths(deploy: 0, run: runMin + surplus);
  }

  Widget _checkForChangesAction() {
    return ValueListenableBuilder<SourceChangesProgress?>(
      valueListenable: _catalog.changesProgress,
      builder: (context, progress, _) => _refreshChangedStatusAction(progress),
    );
  }

  Widget _refreshChangedStatusAction(SourceChangesProgress? progress) {
    final lastCheckedLabel = _lastChangesCheckedLabel(progress);
    final isBusy = _catalog.loading || _catalog.evaluatingChanges;
    final onPressed = isBusy
        ? null
        : () => unawaited(_reload(evaluateChanges: true));
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    final tooltip = lastCheckedLabel == null
        ? 'Refresh changed status'
        : 'Refresh changed status · $lastCheckedLabel';
    final progressIndicator = _catalog.evaluatingChanges
        ? SizedBox(
            width: compact ? 18 : 14,
            height: compact ? 18 : 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress?.fraction,
            ),
          )
        : null;

    if (compact) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: progressIndicator ?? const Icon(Icons.refresh_rounded),
      );
    }

    return SizedBox(
      width: 140,
      child: Tooltip(
        message: tooltip,
        child: ETintedAction.compact(
          accent: onPressed == null ? EColors.textMuted : EColors.accentGlow,
          icon: Icons.refresh_rounded,
          title: 'Refresh',
          subtitle: lastCheckedLabel ?? 'Changed status',
          onActivated: onPressed,
          trailing: progressIndicator,
        ),
      ),
    );
  }

  String? _lastChangesCheckedLabel(SourceChangesProgress? progress) {
    if (_catalog.evaluatingChanges) {
      return progress?.caption ?? 'Checking…';
    }
    final lastCheckedAt = _catalog.lastChangesCheckedAt;
    if (lastCheckedAt == null) return null;
    return lastCheckedAt.relativeTimeAgo();
  }

  Widget _body() {
    if (_catalog.loading && !_catalog.hasProjects) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_catalog.errorMessage != null && !_catalog.hasProjects) {
      return _emptyState();
    }

    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    // Compact: 6px side inset (vs 8) — clears subpixel dual-cluster overflow.
    final listPadH = compact ? 6.0 : ELayout.spaceXl;
    return RefreshIndicator(
      color: EColors.accentGlow,
      backgroundColor: EColors.surface,
      onRefresh: () => _reload(evaluateChanges: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          listPadH,
          ELayout.spaceMd,
          listPadH,
          ELayout.spaceXl + 8,
        ),
        itemCount: _catalog.projects.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: ELayout.spaceMd + 2),
        itemBuilder: (context, index) => _projectRow(_catalog.projects[index]),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: EColors.textMuted,
            ),
            const SizedBox(height: 18),
            Text(
              'No projects available',
              style: EText.section,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            SelectableText(
              _catalog.errorMessage!,
              style: EText.body.medium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => unawaited(_reload(evaluateChanges: false)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _projectRow(WorkbenchProject project) {
    return ProjectWorkbenchRow(
      key: ValueKey(project.projectId),
      project: project,
      platforms: _catalog.platformsFor(project),
      runStateFor: (device) {
        final registry = widget.localRunRegistry;
        if (registry == null) return LocalRunState.idle;
        return registry.stateFor(
          LocalRunKey(projectId: project.projectId, deviceKey: device.key),
        );
      },
      canRunLocally: widget.localRunRegistry != null,
      showLineAge: widget.trigger.showLineAgeAnalysis,
      lineAgeSubtitle: LineAgeCache.instance.slocSubtitleForRepoPath(
        project.path,
      ),
      ongoingDeploy: _activeDeploy.forProject(project.projectId),
      waitingDeploys: _activeDeploy.waiting,
      onLineAge: () => _showLineAgeScreen(project),
      onDeploy: (platform) => unawaited(_deploy(project, platform)),
      onRun: (device) => unawaited(_run(project, device)),
      onStopRun: (device) => unawaited(_stopRun(project, device)),
      onOpenOngoingDeploy: () => unawaited(_showOngoingJobScreen()),
    );
  }
}

class const _HomescreenPaneWidths({
  required final double deploy,
  required final double run,
});
