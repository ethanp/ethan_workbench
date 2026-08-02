import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_errors.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_trigger.dart';
import '../deploy/job_screen.dart';
import '../line_age/line_age_screen.dart';
import '../phone/deploy_http_client.dart';
import '../run/flutter_run_device.dart';
import '../run/local_run_screen.dart';
import '../run/local_run_session.dart';
import '../run/local_run_state.dart';
import 'package:ethan_ui/ethan_ui.dart';

import '../ui/workbench_action_accents.dart';
import '../ui/widgets/deploy_platform_controls.dart';
import 'deployable_project.dart';
import 'project_app_icon_tile.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({required this.trigger, this.localRun});

  final DeployTrigger trigger;
  final LocalRunSession? localRun;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<DeployableProject> _projects = const [];
  bool _loading = true;
  bool _evaluatingChanges = false;
  String? _errorMessage;
  DateTime? _lastChangesCheckedAt;
  Timer? _lastCheckedTicker;
  Timer? _activeJobPoll;
  StreamSubscription<LocalRunState>? _localRunSubscription;
  StreamSubscription<DeployJob>? _jobUpdatesSubscription;
  LocalRunState _localRunState = LocalRunState.idle;
  DeployJob? _ongoingDeploy;

  @override
  void initState() {
    super.initState();
    _lastCheckedTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _lastChangesCheckedAt == null) return;
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
    _listenForOngoingDeploy();
    unawaited(_loadProjects(evaluateChanges: true));
  }

  @override
  void dispose() {
    _lastCheckedTicker?.cancel();
    _activeJobPoll?.cancel();
    unawaited(_localRunSubscription?.cancel());
    unawaited(_jobUpdatesSubscription?.cancel());
    super.dispose();
  }

  void _listenForOngoingDeploy() {
    final jobUpdates = widget.trigger.jobUpdates;
    if (jobUpdates != null) {
      _jobUpdatesSubscription = jobUpdates.listen(_onJobUpdate);
    } else {
      _activeJobPoll = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_refreshOngoingDeploy()),
      );
    }
    unawaited(_refreshOngoingDeploy());
  }

  void _onJobUpdate(DeployJob job) {
    if (!mounted) return;
    setState(() {
      _ongoingDeploy = job.status.isTerminal ? null : job;
    });
  }

  Future<void> _refreshOngoingDeploy() async {
    try {
      final job = await widget.trigger.fetchActiveJob();
      if (!mounted) return;
      setState(() {
        _ongoingDeploy =
            job != null && !job.status.isTerminal ? job : null;
      });
    } on AgentRequestException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        _activeJobPoll?.cancel();
        await widget.trigger.onUnauthorized?.call();
        return;
      }
      // Transient errors: keep the banner until the next successful poll.
    } catch (_) {
      // Banner stays as-is until the next successful poll.
    }
  }

  Future<void> _openOngoingDeploy() async {
    final job = _ongoingDeploy;
    if (job == null) return;
    await _openJobScreen(job);
  }

  Future<void> _openJobScreen(DeployJob job) async {
    setState(() {
      _ongoingDeploy = job.status.isTerminal ? null : job;
    });
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            JobScreen(trigger: widget.trigger, initialJob: job),
      ),
    );
    if (!mounted) return;
    await _refreshOngoingDeploy();
    await _loadProjects(evaluateChanges: true);
  }

  Future<void> _refreshProjects() => _loadProjects(evaluateChanges: false);

  Future<void> _evaluateSourceChanges() {
    if (_evaluatingChanges || _loading) return Future.value();
    return _loadProjects(evaluateChanges: true);
  }

  Future<void> _loadProjects({required bool evaluateChanges}) async {
    setState(() {
      _loading = true;
      _evaluatingChanges = evaluateChanges;
      _errorMessage = null;
    });
    try {
      final projects = evaluateChanges
          ? await widget.trigger.evaluateSourceChanges()
          : await widget.trigger.listProjects();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _loading = false;
        _evaluatingChanges = false;
        if (evaluateChanges) {
          _lastChangesCheckedAt = DateTime.now();
        }
      });
    } on AgentRequestException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        await widget.trigger.onUnauthorized?.call();
        return;
      }
      setState(() {
        final hint = widget.trigger.unreachableHint;
        _errorMessage = evaluateChanges
            ? error.message
            : (hint == null ? error.message : '${error.message}\n\n$hint');
        _loading = false;
        _evaluatingChanges = false;
      });
      if (evaluateChanges && _projects.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _loading = false;
        _evaluatingChanges = false;
      });
      if (evaluateChanges && _projects.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _unpair() async {
    await widget.trigger.onUnpair?.call();
  }

  List<DeployPlatform> _platformsFor(DeployableProject project) {
    return widget.trigger.preferredPlatforms.where(project.supports).toList();
  }

  DeployJob? _ongoingDeployFor(DeployableProject project) {
    final ongoing = _ongoingDeploy;
    if (ongoing == null || ongoing.projectId != project.projectId) return null;
    return ongoing;
  }

  Future<void> _confirmAndDeploy(
    DeployableProject project,
    DeployPlatform platform,
  ) async {
    final sourceStatus = project.sourceStatusFor(platform);
    final force = sourceStatus == DeploySourceStatus.unchanged
        ? await _confirmForceUnchangedDeploy(project, platform)
        : await _confirmNormalDeploy(project, platform);
    if (force == null || !mounted) return;

    try {
      final job = await widget.trigger.startDeploy(
        projectId: project.projectId,
        platform: platform,
        force: force,
      );
      if (!mounted) return;
      await _openJobScreen(job);
    } on DeployAlreadyRunning catch (error) {
      if (!mounted) return;
      try {
        final job = await widget.trigger.fetchJob(error.jobId);
        if (!mounted) return;
        await _openJobScreen(job);
      } catch (_) {
        await _refreshOngoingDeploy();
        if (_ongoingDeploy != null && mounted) {
          await _openJobScreen(_ongoingDeploy!);
        }
      }
    } on AgentRequestException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        await widget.trigger.onUnauthorized?.call();
        return;
      }
      if (error.statusCode == 409) {
        await _refreshOngoingDeploy();
        if (!mounted) return;
        final ongoing = _ongoingDeploy;
        if (ongoing != null) {
          await _openJobScreen(ongoing);
          return;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  /// Returns `false` (incremental) when confirmed, or `null` when cancelled.
  Future<bool?> _confirmNormalDeploy(
    DeployableProject project,
    DeployPlatform platform,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(platform.icon, color: platform.accent, size: 24),
            const SizedBox(width: 12),
            Expanded(child: Text('Deploy ${project.name}?')),
          ],
        ),
        content: Text(
          'Build (if needed) and install to ${platform.label} via deploy.rb.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: platform.accent,
              foregroundColor: EColors.surfaceInset,
            ),
            onPressed: () => Navigator.pop(context, false),
            child: Text('Deploy to ${platform.label}'),
          ),
        ],
      ),
    );
  }

  /// Returns `true` (force) when confirmed, or `null` when cancelled.
  Future<bool?> _confirmForceUnchangedDeploy(
    DeployableProject project,
    DeployPlatform platform,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(platform.icon, color: platform.accent, size: 24),
            const SizedBox(width: 12),
            Expanded(child: Text('No changes for ${platform.label}')),
          ],
        ),
        content: Text(
          '${project.name} matches the last ${platform.label} deploy. '
          'Force a full rebuild and install anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: EColors.warning,
              foregroundColor: EColors.surfaceInset,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Force deploy'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return EScaffoldShell(
      appBar: AppBar(
        title: Text(widget.trigger.title, style: EText.title),
        actions: [
          _checkForChangesAction(),
          if (widget.trigger.showUnpair)
            IconButton(
              tooltip: 'Unpair',
              onPressed: () => unawaited(_unpair()),
              icon: const Icon(Icons.link_off_rounded),
            ),
          const SizedBox(width: ELayout.spaceSm),
        ],
      ),
      body: _body(),
    );
  }

  Widget _checkForChangesAction() {
    final lastCheckedLabel = _lastChangesCheckedLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ELayout.spaceSm),
      child: TextButton(
        onPressed: _loading || _evaluatingChanges
            ? null
            : () => unawaited(_evaluateSourceChanges()),
        style: TextButton.styleFrom(
          backgroundColor: EColors.surfaceRaised.withValues(alpha: 0.55),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: ELayout.borderRadiusMd,
            side: const BorderSide(color: EColors.border),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_evaluatingChanges)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.refresh_rounded, size: 18),
            if (lastCheckedLabel != null) ...[
              const SizedBox(width: ELayout.spaceSm),
              Text(
                lastCheckedLabel,
                style: EText.caption.copyWith(
                  color: EColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? get _lastChangesCheckedLabel {
    if (_evaluatingChanges) return 'Checking…';
    final lastCheckedAt = _lastChangesCheckedAt;
    if (lastCheckedAt == null) return null;
    return lastCheckedAt.relativeTimeAgo();
  }

  Widget _body() {
    if (_loading && _projects.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _projects.isEmpty) {
      return _emptyState();
    }

    return RefreshIndicator(
      color: EColors.accentGlow,
      backgroundColor: EColors.surface,
      onRefresh: () => _loadProjects(evaluateChanges: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          ELayout.spaceXl,
          ELayout.spaceMd,
          ELayout.spaceXl,
          ELayout.spaceXl + 8,
        ),
        itemCount: _projects.length + (_ongoingDeploy != null ? 1 : 0),
        separatorBuilder: (context, index) =>
            const SizedBox(height: ELayout.spaceMd + 2),
        itemBuilder: (context, index) {
          final ongoing = _ongoingDeploy;
          if (ongoing != null) {
            if (index == 0) return _ongoingDeployBanner(ongoing);
            return _projectRow(_projects[index - 1]);
          }
          return _projectRow(_projects[index]);
        },
      ),
    );
  }

  Widget _ongoingDeployBanner(DeployJob job) {
    return ETintedAction(
      accent: EColors.accentGlow,
      icon: Icons.rocket_launch_rounded,
      title: job.projectName,
      subtitle: '${job.platform.label} deploy in progress — tap to open',
      chipLabel: job.status.name,
      chipTone: job.status == DeployJobStatus.queued
          ? EStatusTone.warning
          : EStatusTone.accent,
      onTap: () => unawaited(_openOngoingDeploy()),
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
              _errorMessage!,
              style: EText.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _refreshProjects,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _projectRow(DeployableProject project) {
    final platforms = _platformsFor(project);
    final macosRunStatus = _activeRunStatusFor(project, FlutterRunDevice.macos);
    final meSimRunStatus = _activeRunStatusFor(project, FlutterRunDevice.meSim);
    final showLineAge = widget.trigger.showLineAgeAnalysis;
    final showMacosRun = widget.localRun != null &&
        project.supports(DeployPlatform.macos);
    final showMeSimRun = widget.localRun != null &&
        project.supports(DeployPlatform.ios);
    return ESurface(
      kind: ESurfaceKind.row,
      attention: project.hasChangedSources ||
          macosRunStatus != null ||
          meSimRunStatus != null ||
          _ongoingDeployFor(project) != null,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          ProjectAppIconTile(iconPngBytes: project.iconPngBytes),
          const SizedBox(width: ELayout.spaceLg),
          Expanded(
            flex: 4,
            child: Text(
              project.name,
              style: EText.projectName,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 8,
            child: Row(
              children: [
                if (showLineAge) ...[
                  Expanded(
                    child: ETintedAction(
                      accent: WorkbenchActionAccents.lineAge,
                      icon: Icons.bar_chart_rounded,
                      title: 'Line age',
                      subtitle: 'Authorship over time',
                      onTap: () => _openLineAge(project),
                    ),
                  ),
                  const SizedBox(width: ELayout.spaceSm + 2),
                ],
                if (showMacosRun) ...[
                  Expanded(
                    child: _localRunPlate(
                      project: project,
                      device: FlutterRunDevice.macos,
                      runStatus: macosRunStatus,
                      accent: EColors.success,
                      icon: Icons.desktop_mac_rounded,
                      idleSubtitle: 'macOS debug session',
                    ),
                  ),
                  const SizedBox(width: ELayout.spaceSm + 2),
                ],
                if (showMeSimRun) ...[
                  Expanded(
                    child: _localRunPlate(
                      project: project,
                      device: FlutterRunDevice.meSim,
                      runStatus: meSimRunStatus,
                      accent: EColors.platformIos,
                      icon: Icons.phone_iphone_rounded,
                      idleSubtitle: 'iPhone Simulator',
                    ),
                  ),
                  const SizedBox(width: ELayout.spaceSm + 2),
                ],
                Expanded(
                  flex: platforms.isEmpty ? 1 : platforms.length,
                  child: DeployPlatformActionGroup(
                    platforms: platforms,
                    lastDeployedAt: project.lastDeployedAt,
                    sourceStatus: project.sourceStatus,
                    ongoingDeploy: _ongoingDeployFor(project),
                    onOpenOngoing: () => unawaited(_openOngoingDeploy()),
                    onSelected: (platform) =>
                        unawaited(_confirmAndDeploy(project, platform)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _localRunPlate({
    required DeployableProject project,
    required FlutterRunDevice device,
    required LocalRunStatus? runStatus,
    required Color accent,
    required IconData icon,
    required String idleSubtitle,
  }) {
    return ETintedAction(
      accent: accent,
      icon: runStatus != null ? Icons.play_circle_filled_rounded : icon,
      title: device.label,
      subtitle: runStatus != null
          ? _runStatusSubtitle(runStatus, idleSubtitle: idleSubtitle)
          : idleSubtitle,
      chipLabel: runStatus != null ? _runStatusLabel(runStatus) : null,
      chipTone: runStatus != null ? _runStatusTone(runStatus) : null,
      trailing: _runStopControl(runStatus),
      onTap: () => unawaited(_openLocalRun(project, device)),
    );
  }

  String _runStatusSubtitle(
    LocalRunStatus status, {
    required String idleSubtitle,
  }) =>
      switch (status) {
        LocalRunStatus.starting => 'Starting flutter run…',
        LocalRunStatus.running => 'Session open',
        LocalRunStatus.stopping => 'Stopping…',
        LocalRunStatus.idle ||
        LocalRunStatus.exited ||
        LocalRunStatus.failed => idleSubtitle,
      };

  Widget? _runStopControl(LocalRunStatus? runStatus) {
    if (runStatus != LocalRunStatus.starting &&
        runStatus != LocalRunStatus.running) {
      return null;
    }
    return IconButton(
      tooltip: 'Stop run',
      onPressed: () => unawaited(_stopLocalRun()),
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

  Future<void> _stopLocalRun() async {
    final session = widget.localRun;
    if (session == null || !session.isActive) return;
    try {
      await session.stop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  LocalRunStatus? _activeRunStatusFor(
    DeployableProject project,
    FlutterRunDevice device,
  ) {
    if (_localRunState.projectId != project.projectId) return null;
    if (_localRunState.deviceKey != device.key) return null;
    if (!_localRunState.status.isActive) return null;
    return _localRunState.status;
  }

  String _runStatusLabel(LocalRunStatus status) => switch (status) {
    LocalRunStatus.starting => 'starting',
    LocalRunStatus.running => 'running',
    LocalRunStatus.stopping => 'stopping',
    LocalRunStatus.idle ||
    LocalRunStatus.exited ||
    LocalRunStatus.failed => 'idle',
  };

  EStatusTone _runStatusTone(LocalRunStatus status) => switch (status) {
    LocalRunStatus.starting => EStatusTone.accent,
    LocalRunStatus.running => EStatusTone.success,
    LocalRunStatus.stopping => EStatusTone.warning,
    LocalRunStatus.idle ||
    LocalRunStatus.exited ||
    LocalRunStatus.failed => EStatusTone.muted,
  };

  Future<void> _openLocalRun(
    DeployableProject project,
    FlutterRunDevice device,
  ) async {
    final session = widget.localRun;
    if (session == null) return;

    final activeState = session.state;
    if (activeState.status.isActive &&
        (activeState.projectId != project.projectId ||
            activeState.deviceKey != device.key)) {
      final shouldSwitch = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Stop current run?'),
          content: Text(
            '${activeState.projectName ?? 'Another app'}'
            '${activeState.deviceLabel != null ? ' (${activeState.deviceLabel})' : ''} '
            'is already running. Stop it and run ${project.name} on ${device.label}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Switch'),
            ),
          ],
        ),
      );
      if (shouldSwitch != true || !mounted) return;
      try {
        await session.stop();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
        return;
      }
    }

    try {
      await session.start(project, device: device);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LocalRunScreen(session: session),
      ),
    );
  }

  void _openLineAge(DeployableProject project) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LineAgeScreen(
          repoPath: project.path,
          repoName: project.name,
        ),
      ),
    );
  }
}
