import 'dart:async';

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
import '../line_age/line_age_analyzer.dart';
import '../line_age/line_age_screen.dart';
import '../run/flutter_run_device.dart';
import '../run/local_run_controls.dart';
import '../run/local_run_state.dart';
import 'active_deploy_watch.dart';
import 'deployable_project.dart';
import 'project_deploy_flow.dart';
import 'project_local_run_flow.dart';
import 'project_workbench_row.dart';
import 'projects_catalog.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({required this.trigger, this.localRun});

  final DeployTrigger trigger;
  final LocalRunControls? localRun;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late final ProjectsCatalog _catalog;
  late final ActiveDeployWatch _activeDeploy;
  late final ProjectDeployFlow _deployFlow;
  final _localRunFlow = const ProjectLocalRunFlow();

  Timer? _lastCheckedTicker;
  StreamSubscription<LocalRunState>? _localRunSubscription;
  LocalRunState _localRunState = LocalRunState.idle;

  /// Job shown in the Mac side rail under the queue (null = rail closed).
  DeployJob? _inlineJob;

  static const _queueOnlyWidth = 260.0;
  static const _queueWithJobWidth = 440.0;

  @override
  void initState() {
    super.initState();
    _catalog = ProjectsCatalog(
      trigger: widget.trigger,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    _activeDeploy = ActiveDeployWatch(
      trigger: widget.trigger,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    _deployFlow = ProjectDeployFlow(
      trigger: widget.trigger,
      activeDeploy: _activeDeploy,
      presentJobInline: _presentJobInline,
    );

    _lastCheckedTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _catalog.lastChangesCheckedAt == null) return;
      setState(() {});
    });

    final localRun = widget.localRun;
    if (localRun != null) {
      _localRunState = localRun.state;
      _localRunSubscription = localRun.updates.listen((state) {
        if (!mounted) return;
        setState(() => _localRunState = state);
      });
    }

    _activeDeploy.start();
    unawaited(_reload(evaluateChanges: true));
  }

  @override
  void dispose() {
    _lastCheckedTicker?.cancel();
    unawaited(_localRunSubscription?.cancel());
    unawaited(_activeDeploy.dispose());
    super.dispose();
  }

  Future<void> _reload({required bool evaluateChanges}) async {
    setState(() {});
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
  }

  Future<void> _afterJobScreen() async {
    await _activeDeploy.refresh();
    await _reload(evaluateChanges: true);
  }

  void _presentJobInline(DeployJob job) {
    if (!mounted) return;
    // Phone / compact still uses the full-screen route.
    if (MediaQuery.sizeOf(context).shortestSide < 600) {
      unawaited(_pushJobScreen(job));
      return;
    }
    setState(() => _inlineJob = job);
  }

  Future<void> _pushJobScreen(DeployJob job) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => JobScreen(
          trigger: widget.trigger,
          initialJob: job,
        ),
      ),
    );
    await _afterJobScreen();
  }

  void _closeInlineJob() {
    setState(() => _inlineJob = null);
    unawaited(_afterJobScreen());
  }

  Future<void> _openOngoingDeploy() async {
    final job = _activeDeploy.ongoing;
    if (job == null) return;
    await _deployFlow.showJobScreen(
      context,
      job,
      afterJobScreenClosed: _afterJobScreen,
    );
  }

  Future<void> _deploy(
    DeployableProject project,
    DeployPlatform platform,
  ) {
    return _deployFlow.confirmAndStart(
      context,
      project: project,
      platform: platform,
      afterJobScreenClosed: _afterJobScreen,
    );
  }

  Future<void> _run(
    DeployableProject project,
    FlutterRunDevice device,
  ) async {
    final session = widget.localRun;
    if (session == null) return;
    await _localRunFlow.open(
      context,
      session: session,
      project: project,
      device: device,
    );
  }

  Future<void> _stopRun() async {
    final session = widget.localRun;
    if (session == null) return;
    await _localRunFlow.stop(context, session: session);
  }

  void _openLineAge(DeployableProject project) {
    final gitRoot =
        LineAgeAnalyzer.findGitRoot(project.path) ?? project.path;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LineAgeScreen(
          repoPath: project.path,
          repoName: path.basename(gitRoot),
        ),
      ),
    );
  }

  Future<void> _unpair() async {
    await widget.trigger.onUnpair?.call();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    final showSideRail =
        !compact &&
        (_activeDeploy.hasQueuePanelContent || _inlineJob != null);
    final showJobDetail = !compact && _inlineJob != null;

    return EScaffoldShell(
      contentMaxWidth:
          showSideRail ? double.infinity : ELayout.contentMaxWidth,
      appBar: EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: widget.trigger.title,
        actions: [
          _checkForChangesAction(),
          if (widget.trigger.showUnpair)
            IconButton(
              tooltip: 'Unpair',
              onPressed: () => unawaited(_unpair()),
              icon: const Icon(Icons.link_off_rounded),
            ),
        ],
      ),
      body: showSideRail
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _body()),
                DeployQueuePanel(
                  ongoing: _activeDeploy.ongoing,
                  waiting: _activeDeploy.waiting,
                  ongoingRemaining: _activeDeploy.ongoingRemainingEstimate,
                  width: showJobDetail ? _queueWithJobWidth : _queueOnlyWidth,
                  jobDetail: showJobDetail
                      ? DeployJobDetail(
                          key: ValueKey(_inlineJob!.jobId),
                          trigger: widget.trigger,
                          initialJob: _inlineJob!,
                          embedded: true,
                          onClose: _closeInlineJob,
                          onBecameTerminal: () =>
                              unawaited(_afterJobScreen()),
                        )
                      : null,
                  onOpenOngoing: () => unawaited(_openOngoingDeploy()),
                  onCancelWaiting: (jobId) =>
                      _activeDeploy.cancelWaiting(jobId),
                ),
              ],
            )
          : _body(),
    );
  }

  Widget _checkForChangesAction() {
    final lastCheckedLabel = _lastChangesCheckedLabel;
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
              value: _catalog.changesProgress?.fraction,
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
          onTap: onPressed,
          trailing: progressIndicator,
        ),
      ),
    );
  }

  String? get _lastChangesCheckedLabel {
    if (_catalog.evaluatingChanges) {
      return _catalog.changesProgress?.caption ?? 'Checking…';
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

    final ongoing = _activeDeploy.ongoing;
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
        itemCount: _catalog.projects.length + (ongoing != null ? 1 : 0),
        separatorBuilder: (context, index) =>
            const SizedBox(height: ELayout.spaceMd + 2),
        itemBuilder: (context, index) {
          if (ongoing != null) {
            if (index == 0) {
              return OngoingDeployBanner(
                job: ongoing,
                queuedCount: _activeDeploy.waiting.length,
                onOpen: () => unawaited(_openOngoingDeploy()),
              );
            }
            return _projectRow(_catalog.projects[index - 1]);
          }
          return _projectRow(_catalog.projects[index]);
        },
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
            Text(
              _catalog.errorMessage!,
              style: EText.body,
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

  Widget _projectRow(DeployableProject project) {
    return ProjectWorkbenchRow(
      project: project,
      platforms: _catalog.platformsFor(project),
      localRunState: _localRunState,
      localRun: widget.localRun,
      showLineAge: widget.trigger.showLineAgeAnalysis,
      ongoingDeploy: _activeDeploy.forProject(project.projectId),
      waitingDeploys: _activeDeploy.waiting,
      onLineAge: () => _openLineAge(project),
      onDeploy: (platform) => unawaited(_deploy(project, platform)),
      onRun: (device) => unawaited(_run(project, device)),
      onStopRun: () => unawaited(_stopRun()),
      onOpenOngoingDeploy: () => unawaited(_openOngoingDeploy()),
    );
  }
}
