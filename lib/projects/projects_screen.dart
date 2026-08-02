import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_platform.dart';
import '../deploy/deploy_trigger.dart';
import '../deploy/job_screen.dart';
import '../phone/deploy_http_client.dart';
import 'package:ethan_ui/ethan_ui.dart';

import '../ui/widgets/deploy_platform_controls.dart';
import 'deployable_project.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({required this.trigger});

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
    _lastCheckedTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _lastChangesCheckedAt == null) return;
      setState(() {});
    });
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
          builder: (context) =>
              JobScreen(trigger: widget.trigger, initialJob: job),
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
            borderRadius: ELayout.borderRadius(ELayout.radiusMd),
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
        itemCount: _projects.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: ELayout.spaceMd + 2),
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
    return ESurface(
      kind: ESurfaceKind.row,
      attention: project.hasChangedSources,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          _projectAppIcon(project),
          const SizedBox(width: ELayout.spaceLg),
          Expanded(
            flex: 5,
            child: Text(
              project.name,
              style: EText.projectName,
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
    );
  }

  Widget _projectAppIcon(DeployableProject project) {
    final iconPngBytes = project.iconPngBytes;
    final radius = ELayout.borderRadius(ELayout.radiusLg);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: ELayout.iconTile,
          height: ELayout.iconTile,
          child: iconPngBytes == null
              ? const ColoredBox(
                  color: EColors.surfaceInset,
                  child: Icon(
                    Icons.apps_rounded,
                    size: 34,
                    color: EColors.textMuted,
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
