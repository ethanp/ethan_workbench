import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_platform.dart';
import '../deploy/deploy_trigger.dart';
import '../deploy/job_screen.dart';
import '../phone/deploy_http_client.dart';
import '../ui/theme/app_colors.dart';
import '../ui/theme/app_text.dart';
import '../ui/widgets/deploy_platform_controls.dart';
import 'deployable_project.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({
    super.key,
    required this.trigger,
  });

  final DeployTrigger trigger;

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

  @override
  void initState() {
    super.initState();
    _lastCheckedTicker = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (!mounted || _lastChangesCheckedAt == null) return;
        setState(() {});
      },
    );
    unawaited(_loadProjects(evaluateChanges: true));
  }

  @override
  void dispose() {
    _lastCheckedTicker?.cancel();
    super.dispose();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _loading = false;
        _evaluatingChanges = false;
      });
      if (evaluateChanges && _projects.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> _unpair() async {
    await widget.trigger.onUnpair?.call();
  }

  List<DeployPlatform> _platformsFor(DeployableProject project) {
    return widget.trigger.preferredPlatforms
        .where(project.supports)
        .toList();
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
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => JobScreen(
            trigger: widget.trigger,
            initialJob: job,
          ),
        ),
      );
      if (!mounted) return;
      await _loadProjects(evaluateChanges: true);
    } on AgentRequestException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        await widget.trigger.onUnauthorized?.call();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
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
            Expanded(
              child: Text('Deploy ${project.name}?'),
            ),
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
              foregroundColor: AppColors.surfaceInset,
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
            Expanded(
              child: Text('No changes for ${platform.label}'),
            ),
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
              backgroundColor: AppColors.warning,
              foregroundColor: AppColors.surfaceInset,
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background.withValues(alpha: 0.92),
        title: Text(widget.trigger.title, style: AppText.title),
        actions: [
          _checkForChangesAction(),
          if (widget.trigger.showUnpair)
            IconButton(
              tooltip: 'Unpair',
              onPressed: () => unawaited(_unpair()),
              icon: const Icon(Icons.link_off_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: AppColors.scaffoldGradient,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 220,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.ambientGlowGradient,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: _body(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkForChangesAction() {
    final lastCheckedLabel = _lastChangesCheckedLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextButton(
        onPressed: _loading || _evaluatingChanges
            ? null
            : () => unawaited(_evaluateSourceChanges()),
        style: TextButton.styleFrom(
          backgroundColor: AppColors.surfaceRaised.withValues(alpha: 0.65),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
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
              const SizedBox(width: 8),
              Text(
                lastCheckedLabel,
                style: AppText.caption.copyWith(
                  color: AppColors.textSecondary,
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
      color: AppColors.accentGlow,
      backgroundColor: AppColors.surface,
      onRefresh: () => _loadProjects(evaluateChanges: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        itemCount: _projects.length,
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemBuilder: (context, index) => _projectRow(_projects[index]),
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
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 18),
            Text(
              'No projects available',
              style: AppText.section,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: AppText.body,
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
    final changed = project.hasChangedSources;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.rowGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: changed
              ? AppColors.warning.withValues(alpha: 0.35)
              : AppColors.border.withValues(alpha: 0.9),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          if (changed)
            BoxShadow(
              color: AppColors.warning.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 0),
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _projectAppIcon(project),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: Text(
                project.name,
                style: AppText.projectName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 7,
              child: DeployPlatformActionGroup(
                platforms: platforms,
                lastDeployedAt: project.lastDeployedAt,
                sourceStatus: project.sourceStatus,
                onSelected: (platform) =>
                    unawaited(_confirmAndDeploy(project, platform)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _projectAppIcon(DeployableProject project) {
    final iconPngBytes = project.iconPngBytes;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 72,
          height: 72,
          child: iconPngBytes == null
              ? const ColoredBox(
                  color: AppColors.surfaceInset,
                  child: Icon(
                    Icons.apps_rounded,
                    size: 34,
                    color: AppColors.textMuted,
                  ),
                )
              : Image.memory(
                  iconPngBytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
        ),
      ),
    );
  }
}
