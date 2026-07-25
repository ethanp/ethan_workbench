import 'dart:async';

import 'package:flutter/material.dart';

import '../agent/agent_endpoint.dart';
import '../api/deploy_client.dart';
import '../api/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_panel.dart';
import 'job_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late final DeployClient _client;
  List<DeployableProject> _projects = const [];
  bool _loading = true;
  bool _forceDeploy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _client = DeployClient();
    unawaited(_refreshProjects());
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _refreshProjects() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final projects = await _client.listProjects();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _loading = false;
      });
    } on DeployClientException catch (error) {
      if (!mounted) return;
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
      final job = await _client.startDeploy(
        projectId: project.projectId,
        force: _forceDeploy,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => JobScreen(
            client: _client,
            initialJob: job,
          ),
        ),
      );
    } on DeployClientException catch (error) {
      if (!mounted) return;
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
