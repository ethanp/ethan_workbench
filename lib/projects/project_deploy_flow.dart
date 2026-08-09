import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_errors.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_trigger.dart';
import '../deploy/job_screen.dart';
import '../phone/deploy_http_client.dart';
import 'active_deploy_watch.dart';
import 'deployable_project.dart';

/// Confirm → start deploy → present job UI, or enqueue when busy.
class ProjectDeployFlow {
  ProjectDeployFlow({
    required this.trigger,
    required this.activeDeploy,
    this.presentJobInline,
  });

  final DeployTrigger trigger;
  final ActiveDeployWatch activeDeploy;

  /// When set (Mac wide workbench), show the job in the side rail instead of
  /// pushing [JobScreen].
  final void Function(DeployJob job)? presentJobInline;

  Future<void> showJobScreen(
    BuildContext context,
    DeployJob job, {
    required Future<void> Function() afterJobScreenClosed,
  }) async {
    activeDeploy.remember(job);
    final presentInline = presentJobInline;
    if (presentInline != null) {
      presentInline(job);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => JobScreen(trigger: trigger, initialJob: job),
      ),
    );
    await afterJobScreenClosed();
  }

  Future<void> confirmAndStart(
    BuildContext context, {
    required DeployableProject project,
    required DeployPlatform platform,
    required Future<void> Function() afterJobScreenClosed,
  }) async {
    final ongoing = activeDeploy.ongoing;
    if (ongoing != null &&
        ongoing.status.isActiveRunner &&
        ongoing.projectId == project.projectId &&
        ongoing.platform == platform) {
      await showJobScreen(
        context,
        ongoing,
        afterJobScreenClosed: afterJobScreenClosed,
      );
      return;
    }

    final alreadyWaiting = activeDeploy.waitingFor(
      projectId: project.projectId,
      platformName: platform.name,
    );
    if (alreadyWaiting != null) {
      if (!context.mounted) return;
      context.textSnackBar(
        'Already queued: ${project.name} (${platform.label})',
      );
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
      if (job.status.isWaiting) {
        await activeDeploy.refresh();
        if (!context.mounted) return;
        final behind = activeDeploy.ongoing?.projectName ?? 'current deploy';
        context.textSnackBar('Queued ${project.name} behind $behind');
        return;
      }
      await showJobScreen(
        context,
        job,
        afterJobScreenClosed: afterJobScreenClosed,
      );
    } on DeployAlreadyQueued catch (error) {
      if (!context.mounted) return;
      await activeDeploy.refresh();
      if (!context.mounted) return;
      context.textSnackBar(error.toString());
    } on DeployAlreadyRunning catch (error) {
      if (!context.mounted) return;
      await _showConflictingJob(
        context,
        error,
        afterJobScreenClosed: afterJobScreenClosed,
      );
    } on ServerRequestException catch (error) {
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
          await showJobScreen(
            context,
            refreshed,
            afterJobScreenClosed: afterJobScreenClosed,
          );
          return;
        }
      }
      if (!context.mounted) return;
      context.textSnackBar(error.message);
    } catch (error) {
      if (!context.mounted) return;
      context.textSnackBar(error.toString());
    }
  }

  Future<void> _showConflictingJob(
    BuildContext context,
    DeployAlreadyRunning error, {
    required Future<void> Function() afterJobScreenClosed,
  }) async {
    final knownJob = error.job;
    if (knownJob != null) {
      await showJobScreen(
        context,
        knownJob,
        afterJobScreenClosed: afterJobScreenClosed,
      );
      return;
    }
    try {
      final job = await trigger.fetchJob(error.jobId);
      if (!context.mounted) return;
      await showJobScreen(
        context,
        job,
        afterJobScreenClosed: afterJobScreenClosed,
      );
    } catch (_) {
      await activeDeploy.refresh();
      final ongoing = activeDeploy.ongoing;
      if (ongoing != null && context.mounted) {
        await showJobScreen(
          context,
          ongoing,
          afterJobScreenClosed: afterJobScreenClosed,
        );
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
