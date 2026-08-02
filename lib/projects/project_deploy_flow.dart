import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_errors.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_trigger.dart';
import '../deploy/job_screen.dart';
import '../phone/deploy_http_client.dart';
import '../ui/widgets/deploy_platform_controls.dart';
import 'active_deploy_watch.dart';
import 'deployable_project.dart';

/// Confirm → start deploy → open [JobScreen], including conflict rejoin.
class ProjectDeployFlow {
  const ProjectDeployFlow({required this.trigger, required this.activeDeploy});

  final DeployTrigger trigger;
  final ActiveDeployWatch activeDeploy;

  Future<void> openJob(
    BuildContext context,
    DeployJob job, {
    required Future<void> Function() onReturned,
  }) async {
    activeDeploy.remember(job);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => JobScreen(trigger: trigger, initialJob: job),
      ),
    );
    await onReturned();
  }

  Future<void> confirmAndStart(
    BuildContext context, {
    required DeployableProject project,
    required DeployPlatform platform,
    required Future<void> Function() onReturned,
  }) async {
    final ongoing = activeDeploy.ongoing;
    if (ongoing != null &&
        !ongoing.status.isTerminal &&
        ongoing.projectId == project.projectId &&
        ongoing.platform == platform) {
      await openJob(context, ongoing, onReturned: onReturned);
      return;
    }

    final sourceStatus = project.sourceStatusFor(platform);
    final force = sourceStatus == DeploySourceStatus.unchanged
        ? await _confirmForceUnchanged(context, project, platform)
        : await _confirmNormal(context, project, platform);
    if (force == null || !context.mounted) return;

    try {
      final job = await trigger.startDeploy(
        projectId: project.projectId,
        platform: platform,
        force: force,
      );
      if (!context.mounted) return;
      await openJob(context, job, onReturned: onReturned);
    } on DeployAlreadyRunning catch (error) {
      if (!context.mounted) return;
      await _openConflict(context, error, onReturned: onReturned);
    } on AgentRequestException catch (error) {
      if (!context.mounted) return;
      if (error.isUnauthorized) {
        await trigger.onUnauthorized?.call();
        return;
      }
      if (error.statusCode == 409) {
        await activeDeploy.refresh();
        if (!context.mounted) return;
        final refreshed = activeDeploy.ongoing;
        if (refreshed != null) {
          await openJob(context, refreshed, onReturned: onReturned);
          return;
        }
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openConflict(
    BuildContext context,
    DeployAlreadyRunning error, {
    required Future<void> Function() onReturned,
  }) async {
    final knownJob = error.job;
    if (knownJob != null) {
      await openJob(context, knownJob, onReturned: onReturned);
      return;
    }
    try {
      final job = await trigger.fetchJob(error.jobId);
      if (!context.mounted) return;
      await openJob(context, job, onReturned: onReturned);
    } catch (_) {
      await activeDeploy.refresh();
      final ongoing = activeDeploy.ongoing;
      if (ongoing != null && context.mounted) {
        await openJob(context, ongoing, onReturned: onReturned);
      }
    }
  }

  Future<bool?> _confirmNormal(
    BuildContext context,
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

  Future<bool?> _confirmForceUnchanged(
    BuildContext context,
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
}
