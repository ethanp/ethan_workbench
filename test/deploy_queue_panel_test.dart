import 'package:ethan_workbench/deploy/deploy_job.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/deploy/deploy_queue_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DeployJob _deployJob({required String jobId, required DeployJobStatus status}) {
  return DeployJob(
    jobId: jobId,
    projectId: jobId,
    projectName: jobId,
    platform: DeployPlatform.macos,
    force: false,
    status: status,
    log: '',
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  testWidgets('Up next jobs show drag handles; Now does not', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeployQueuePanel(
            ongoing: _deployJob(jobId: 'now', status: DeployJobStatus.running),
            waiting: [
              _deployJob(jobId: 'first', status: DeployJobStatus.waiting),
              _deployJob(jobId: 'second', status: DeployJobStatus.waiting),
            ],
            onOpenOngoing: () {},
            onCancelOngoing: () async {},
            onCancelWaiting: (_) async {},
            onReorderWaiting: ({required jobId, required toIndex}) async {},
          ),
        ),
      ),
    );

    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(2));
  });

  testWidgets('Now tile cancels the ongoing deploy', (tester) async {
    var cancelCount = 0;
    var openCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeployQueuePanel(
            ongoing: _deployJob(jobId: 'now', status: DeployJobStatus.running),
            waiting: [
              _deployJob(jobId: 'first', status: DeployJobStatus.waiting),
            ],
            onOpenOngoing: () => openCount++,
            onCancelOngoing: () async => cancelCount++,
            onCancelWaiting: (_) async {},
            onReorderWaiting: ({required jobId, required toIndex}) async {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Cancel deploy'), findsOneWidget);
    expect(find.byTooltip('Remove from queue'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel deploy'));
    await tester.pump();
    expect(cancelCount, 1);
    expect(openCount, 0);
  });
}
