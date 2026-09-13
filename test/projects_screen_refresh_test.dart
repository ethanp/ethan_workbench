import 'package:ethan_workbench/deploy/deploy_job.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/deploy/deploy_run_record.dart';
import 'package:ethan_workbench/deploy/deploy_trigger.dart';
import 'package:ethan_workbench/projects/projects_screen.dart';
import 'package:ethan_workbench/projects/source_changes_progress.dart';
import 'package:ethan_workbench/projects/workbench_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('automatically rechecks source changes every 30 seconds', (
    tester,
  ) async {
    var sourceChangeEvaluations = 0;
    const project = WorkbenchProject(
      projectId: 'book_track',
      name: 'book_track',
      path: '/tmp/book_track',
      platforms: {DeployPlatform.ios},
    );
    final trigger = DeployTrigger(
      listProjects: () async => const [project],
      evaluateSourceChanges:
          ({void Function(SourceChangesProgress progress)? onProgress}) async {
            sourceChangeEvaluations++;
            return const [project];
          },
      startDeploy: ({
        required String projectId,
        required DeployPlatform platform,
        bool force = false,
      }) async => throw UnimplementedError(),
      fetchJob: (jobId) async => throw UnimplementedError(),
      fetchActiveJob: () async => null,
      listDeployHistory: () async => const <DeployRunRecord>[],
      fetchDeployQueue: () async => const <DeployJob>[],
      cancelQueuedDeploy: (jobId) async {},
    );

    await tester.pumpWidget(
      MaterialApp(home: ProjectsScreen(trigger: trigger)),
    );
    await tester.pump();
    expect(sourceChangeEvaluations, 1);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(sourceChangeEvaluations, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
