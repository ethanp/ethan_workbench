import 'dart:async';

import 'package:flutter/material.dart';

import '../agent/agent_endpoint.dart';
import '../deploy/job_screen.dart';
import '../phone/deploy_http_client.dart';
import '../phone/phone_deploy_session.dart';
import '../ui/theme/app_colors.dart';
import '../ui/theme/app_text.dart';
import '../ui/widgets/app_panel.dart';
import 'deployable_project.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({
    super.key,
    required this.session,
    required this.onUnauthorized,
  });

  final PhoneDeploySession session;
  final Future<void> Function() onUnauthorized;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<DeployableProject> _projects = const [];
  bool _loading = true;
  bool _forceDeploy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshProjects());
  }

  Future<void> _refreshProjects() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final projects = await widget.session.listProjects();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _loading = false;
      });
    } on AgentRequestException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        await widget.onUnauthorized();
        return;
      }
      setState(() {
        _errorMessage =
            '${error.message}\n\nIs the Mac companion running at '
            '$phoneDeployAgentBaseUrl?';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _unpair() async {
    await widget.session.unpair();
    await widget.onUnauthorized();
  }

  Future<void> _confirmAndDeploy(DeployableProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Deploy ${project.name}?'),
        content: Text(
          _forceDeploy
              ? 'Force rebuild and install via the Mac companion.'
              : 'Build (if needed) and install via the Mac companion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deploy'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final job = await widget.session.startDeploy(
        projectId: project.projectId,
        force: _forceDeploy,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => JobScreen(
            session: widget.session,
            initialJob: job,
            onUnauthorized: widget.onUnauthorized,
          ),
        ),
      );
    } on AgentRequestException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        await widget.onUnauthorized();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phone Deploy'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refreshProjects,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Unpair',
            onPressed: () => unawaited(_unpair()),
            icon: const Icon(Icons.link_off_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _forceRebuildToggle(),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _forceRebuildToggle() {
    return AppPanel(
      title: 'Options',
      subtitle: _forceDeploy ? 'Force rebuild on' : 'Incremental deploy',
      trailing: Switch(
        value: _forceDeploy,
        onChanged: (value) => setState(() => _forceDeploy = value),
      ),
      child: Text(
        'When on, passes --force to deploy.rb.',
        style: AppText.body,
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _projects.isEmpty) {
      return _emptyState();
    }

    return RefreshIndicator(
      color: AppColors.accentGlow,
      backgroundColor: AppColors.surface,
      onRefresh: _refreshProjects,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _projects.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _projectTile(_projects[index]),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'Can’t reach the Mac agent',
              style: AppText.section,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: AppText.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _refreshProjects,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _projectTile(DeployableProject project) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(_confirmAndDeploy(project)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.rocket_launch_rounded,
                  color: AppColors.accentGlow,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name, style: AppText.section),
                    const SizedBox(height: 2),
                    Text(project.projectId, style: AppText.caption),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
