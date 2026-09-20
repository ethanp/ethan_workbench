import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_errors.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_trigger.dart';
import '../deploy/job_screen.dart';
import '../phone/deploy_http_client.dart';
import 'active_deploy_watch.dart';
import 'workbench_project.dart';

/// Start deploy → show job UI, or enqueue when busy.
class ProjectDeployFlow({
  required final DeployTrigger trigger,
  required final ActiveDeployWatch activeDeploy,

  /// When set (Mac wide workbench), show the job in the side rail instead of
  /// pushing [JobScreen].
  final void Function(DeployJob job)? showJobInSideRailOrJobScreen,
}) {
  Future<void> showJobScreen(
    BuildContext context,
    DeployJob job, {
    required Future<void> Function() afterJobScreenClosed,
  }) async {
    activeDeploy.remember(job);
    final showInRailOrJobScreen = showJobInSideRailOrJobScreen;
    if (showInRailOrJobScreen != null) {
      showInRailOrJobScreen(job);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => JobScreen(trigger: trigger, initialJob: job),
      ),
    );
    await afterJobScreenClosed();
  }

  Future<void> startChangedDeploys(
    BuildContext context, {
    required List<WorkbenchProject> projects,
    required Future<void> Function() afterJobScreenClosed,
  }) async {
    final changedDeploys = [
      for (final project in projects)
        for (final platform in project.changedPlatforms)
          _ChangedDeploy(project: project, platform: platform),
    ];
    if (changedDeploys.isEmpty) {
      if (context.mounted) {
        context.textSnackBar('No changed deploys.');
      }
      return;
    }

    DeployJob? firstStarted;
    var queuedCount = 0;
    for (final changedDeploy in changedDeploys) {
      if (!context.mounted) return;
      if (activeDeploy.ongoing?.status.isActiveRunner == true &&
          activeDeploy.ongoing?.projectId == changedDeploy.project.projectId &&
          activeDeploy.ongoing?.platform == changedDeploy.platform) {
        continue;
      }
      if (activeDeploy.waitingFor(
            projectId: changedDeploy.project.projectId,
            platformName: changedDeploy.platform.name,
          ) !=
          null) {
        continue;
      }
      try {
        final job = await trigger.startDeploy(
          projectId: changedDeploy.project.projectId,
          platform: changedDeploy.platform,
          force: false,
        );
        if (job.status.isWaiting) {
          queuedCount++;
          await activeDeploy.refresh();
        } else {
          firstStarted ??= job;
          await activeDeploy.refresh();
        }
      } on DeployAlreadyQueued {
        await activeDeploy.refresh();
      } on DeployAlreadyRunning {
        await activeDeploy.refresh();
      } on ServerRequestException catch (error) {
        if (!context.mounted) return;
        if (error.isUnauthorized) {
          await trigger.onUnauthorized?.call();
          return;
        }
        context.textSnackBar(error.message);
        return;
      } catch (error) {
        if (!context.mounted) return;
        context.textSnackBar(error.toString());
        return;
      }
    }

    if (!context.mounted) return;
    if (firstStarted != null) {
      await showJobScreen(
        context,
        firstStarted,
        afterJobScreenClosed: afterJobScreenClosed,
      );
    }
    if (!context.mounted) return;
    if (queuedCount > 0) {
      context.textSnackBar(
        queuedCount == 1
            ? 'Queued 1 changed deploy'
            : 'Queued $queuedCount changed deploys',
      );
    }
  }

  Future<void> startDeploy(
    BuildContext context, {
    required WorkbenchProject project,
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

    try {
      final job = await trigger.startDeploy(
        projectId: project.projectId,
        platform: platform,
        force: false,
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
}

class const _ChangedDeploy({
  required final WorkbenchProject project,
  required final DeployPlatform platform,
});
