import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../app_identity.dart';
import '../commit/commit_screen.dart';
import '../commit/uncommitted_changes_cache.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_trigger.dart';
import '../deploy/job_screen.dart';
import '../line_age/line_age_analyzer.dart';
import '../line_age/line_age_cache.dart';
import '../line_age/line_age_screen.dart';
import '../line_age/flutter_line_age.dart';
import '../ui/workbench_action_accents.dart';
import '../run/flutter_run_device.dart';
import '../run/local_run_controls.dart';
import '../run/local_run_key.dart';
import '../run/local_run_registry.dart';
import '../run/local_run_screen.dart';
import '../run/local_run_state.dart';
import 'active_deploy_watch.dart';
import 'homescreen_rail_selection.dart';
import 'homescreen_source_cache.dart';
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
  late final HomescreenSourceCache _sourceCache;
  late final HomescreenRailSelection _rails;

  Timer? _sourceChangesRefreshTimer;
  StreamSubscription<void>? _localRunSubscription;

  @override
  void initState() {
    super.initState();
    _sourceCache = HomescreenSourceCache(
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    _rails = HomescreenRailSelection(
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
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
        setState(() => _rails.keepBuildLogOnNowJob(_activeDeploy.ongoing));
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
      _rails.adoptRestoredActiveRunInRail(localRunRegistry);
      _localRunSubscription = localRunRegistry.changes.listen((_) {
        if (!mounted) return;
        setState(() => _rails.adoptRestoredActiveRunInRail(localRunRegistry));
      });
    }

    _activeDeploy.start();
    _sourceCache.listenToUncommittedChanges();
    unawaited(_sourceCache.loadPersistedLineAge());
    unawaited(_reload(evaluateChanges: true));
  }

  @override
  void dispose() {
    _sourceChangesRefreshTimer?.cancel();
    _sourceCache.stopListeningToUncommittedChanges();
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
    if (widget.trigger.showLineAgeAnalysis) {
      unawaited(
        _sourceCache.refreshUncommitted(
          _catalog.projects.map((project) => project.path),
        ),
      );
    }
    if (analyzeLineAgeAfterLoad &&
        outcome == ProjectsCatalogLoadOutcome.succeeded &&
        widget.trigger.showLineAgeAnalysis) {
      unawaited(
        _sourceCache.blameDistinctGitRoots(
          flutterRoots: widget.trigger.flutterRoots,
        ),
      );
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
    if (MediaQuery.sizeOf(context).shortestSide < 600) {
      unawaited(_pushJobScreen(job));
      return;
    }
    _rails.showJobInSideRail(job);
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
    _rails.closeInlineJob();
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
    _rails.showRunInSideRail(controls);
  }

  void _selectRunInPane(LocalRunKey runKey) {
    final registry = widget.localRunRegistry;
    if (registry == null) return;
    _showRunInSideRailOrRunScreen(registry.controlsFor(runKey));
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
    return _deployFlow.startDeploy(
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

  Widget _deployChangedAction() {
    var changedCount = 0;
    for (final project in _catalog.projects) {
      changedCount += project.changedPlatforms.length;
    }
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    final onActivated = changedCount == 0
        ? null
        : () => unawaited(
            _deployFlow.startChangedDeploys(
              context,
              projects: _catalog.projects,
              afterJobScreenClosed: _afterJobScreenClosed,
            ),
          );
    if (compact) {
      return IconButton(
        tooltip: changedCount == 0
            ? 'Deploy changed · none'
            : 'Deploy changed · $changedCount',
        onPressed: onActivated,
        icon: const Icon(Icons.rocket_launch_rounded),
      );
    }
    return ETintedAction.compact(
      accent: changedCount == 0 ? EColors.textMuted : EColors.accentGlow,
      icon: Icons.rocket_launch_rounded,
      title: 'Deploy changed',
      subtitle: changedCount == 0 ? 'None' : '$changedCount',
      onActivated: onActivated,
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
    return ETintedAction.compact(
      accent: WorkbenchActionAccents.lineAge,
      icon: Icons.bar_chart_rounded,
      title: 'Line age',
      subtitle: subtitle,
      onActivated: _showFlutterLineAgeScreen,
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

  Future<void> _showCommitScreen(WorkbenchProject project) async {
    final gitRoot = LineAgeAnalyzer.findGitRoot(project.path) ?? project.path;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CommitScreen(
          gitRoot: gitRoot,
          repoName: path.basename(gitRoot),
        ),
      ),
    );
    await UncommittedChangesCache.instance.refresh(gitRoot);
  }

  Future<void> _signOut() async {
    await widget.trigger.onSignOut?.call();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    final showSideRail = _rails.showSideRail(
      compact: compact,
      hasQueuePanelContent: _activeDeploy.hasQueuePanelContent,
    );

    return EScaffoldShell(
      contentMaxWidth: showSideRail ? double.infinity : ELayout.contentMaxWidth,
      appBar: EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: widget.trigger.title,
        actions: [
          _deployChangedAction(),
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

  Widget _bodyWithSideRail({required bool compact}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paneWidths = _rails.paneWidths(
          totalWidth: constraints.maxWidth,
          compact: compact,
          platformCount: widget.trigger.preferredPlatforms.length,
          showLineAge: widget.trigger.showLineAgeAnalysis,
          showCommit: widget.trigger.showLineAgeAnalysis,
          hasQueuePanelContent: _activeDeploy.hasQueuePanelContent,
        );
        return HomescreenSideRails(
          list: _body(),
          paneWidths: paneWidths,
          deployPane: paneWidths.deploy > 0
              ? HomescreenDeployPane(
                  width: paneWidths.deploy,
                  activeDeploy: _activeDeploy,
                  trigger: widget.trigger,
                  inlineJob: _rails.inlineJob,
                  onShowJob: _showJobInSideRailOrJobScreen,
                  onDismiss: _closeInlineJob,
                  onOpenOngoing: () => unawaited(_showOngoingJobScreen()),
                )
              : null,
          runPane: paneWidths.run > 0
              ? HomescreenRunPane(
                  width: paneWidths.run,
                  inlineRun: _rails.inlineRun!,
                  sessions: _rails.runPaneSessions(widget.localRunRegistry),
                  onSessionSelected: _selectRunInPane,
                  onDismiss: _rails.closeInlineRun,
                )
              : null,
        );
      },
    );
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

    return Tooltip(
      message: tooltip,
      child: ETintedAction.compact(
        accent: onPressed == null ? EColors.textMuted : EColors.accentGlow,
        icon: Icons.refresh_rounded,
        title: 'Refresh',
        subtitle: lastCheckedLabel ?? 'Changed status',
        onActivated: onPressed,
        trailing: progressIndicator,
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
      showCommit:
          widget.trigger.showLineAgeAnalysis &&
          LineAgeAnalyzer.findGitRoot(project.path) != null,
      uncommittedChanges: UncommittedChangesCache.instance.countsForRepoPath(
        project.path,
      ),
      ongoingDeploy: _activeDeploy.forProject(project.projectId),
      waitingDeploys: _activeDeploy.waiting,
      onLineAge: () => _showLineAgeScreen(project),
      onCommit: () => unawaited(_showCommitScreen(project)),
      onDeploy: (platform) => unawaited(_deploy(project, platform)),
      onRun: (device) => unawaited(_run(project, device)),
      onStopRun: (device) => unawaited(_stopRun(project, device)),
      onOpenOngoingDeploy: () => unawaited(_showOngoingJobScreen()),
    );
  }
}
