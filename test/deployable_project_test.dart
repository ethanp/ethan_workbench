import 'package:ethan_workbench/deploy/deploy_job.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/deploy/deploy_run_record.dart';
import 'package:ethan_workbench/deploy/deploy_trigger.dart';
import 'package:ethan_workbench/projects/deployable_project.dart';
import 'package:ethan_workbench/projects/projects_catalog.dart';
import 'package:ethan_workbench/projects/source_changes_progress.dart';
import 'package:flutter_test/flutter_test.dart';

DeployableProject _project(
  String id, {
  DeploySourceStatus iosStatus = DeploySourceStatus.changed,
  DateTime? iosDeployedAt,
}) {
  return DeployableProject(
    projectId: id,
    name: id,
    path: '/tmp/$id',
    platforms: {DeployPlatform.ios, DeployPlatform.macos},
    sourceStatus: {
      DeployPlatform.ios: iosStatus,
      DeployPlatform.macos: DeploySourceStatus.unchanged,
    },
    lastDeployedAt: {
      DeployPlatform.ios: iosDeployedAt ?? DateTime(2026, 8, 24),
    },
  );
}

DeployJob _succeededJob({
  required String projectId,
  required DateTime finishedAt,
}) {
  return DeployJob(
    jobId: 'job-1',
    projectId: projectId,
    projectName: projectId,
    platform: DeployPlatform.ios,
    force: false,
    status: DeployJobStatus.succeeded,
    log: '',
    createdAt: finishedAt.subtract(const Duration(minutes: 2)),
    finishedAt: finishedAt,
  );
}

DeployTrigger _unusedTrigger() {
  return DeployTrigger(
    listProjects: () async => const [],
    evaluateSourceChanges:
        ({void Function(SourceChangesProgress progress)? onProgress}) async =>
            const [],
    startDeploy:
        ({
          required String projectId,
          required DeployPlatform platform,
          bool force = false,
        }) async =>
            throw UnimplementedError(),
    fetchJob: (jobId) async => throw UnimplementedError(),
    fetchActiveJob: () async => null,
    listDeployHistory: () async => const <DeployRunRecord>[],
    fetchDeployQueue: () async => const [],
    cancelQueuedDeploy: (jobId) async {},
  );
}

void main() {
  test('withSuccessfulDeploy marks that platform current at finished time', () {
    final previousDeploy = DateTime(2026, 8, 24);
    final justFinished = DateTime(2026, 8, 29, 13, 20);
    final updated = _project(
      'health_notes',
      iosDeployedAt: previousDeploy,
    ).withSuccessfulDeploy(
      platform: DeployPlatform.ios,
      deployedAt: justFinished,
    );

    expect(
      updated.sourceStatusFor(DeployPlatform.ios),
      DeploySourceStatus.unchanged,
    );
    expect(updated.lastDeployedAtFor(DeployPlatform.ios), justFinished);
    expect(
      updated.sourceStatusFor(DeployPlatform.macos),
      DeploySourceStatus.unchanged,
    );
  });

  test('applySuccessfulDeploy updates the matching project and re-sorts', () {
    final catalog = ProjectsCatalog(trigger: _unusedTrigger());
    catalog.projects = [
      _project('health_notes'),
      _project('tagger_fl'),
    ];
    final finishedAt = DateTime(2026, 8, 29, 13, 20);

    catalog.applySuccessfulDeploy(
      _succeededJob(projectId: 'health_notes', finishedAt: finishedAt),
    );

    expect(catalog.projects.map((project) => project.projectId), [
      'tagger_fl',
      'health_notes',
    ]);
    final healthNotes = catalog.projects.last;
    expect(
      healthNotes.sourceStatusFor(DeployPlatform.ios),
      DeploySourceStatus.unchanged,
    );
    expect(healthNotes.lastDeployedAtFor(DeployPlatform.ios), finishedAt);
  });
}
