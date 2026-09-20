import 'package:ethan_workbench/deploy/deploy_job.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/deploy/deploy_queue_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DeployJob _deployJob({
  required String jobId,
  required DeployJobStatus status,
}) {
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
            onCancelWaiting: (_) async {},
            onReorderWaiting: ({required jobId, required toIndex}) async {},
          ),
        ),
      ),
    );

    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(2));
    expect(find.text('Nothing queued'), findsNothing);
  });

  testWidgets('Restart after queue is a trailing Up next row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeployQueuePanel(
            ongoing: _deployJob(jobId: 'now', status: DeployJobStatus.running),
            waiting: [
              _deployJob(jobId: 'first', status: DeployJobStatus.waiting),
            ],
            restartAfterQueue: true,
            onOpenOngoing: () {},
            onCancelWaiting: (_) async {},
            onReorderWaiting: ({required jobId, required toIndex}) async {},
          ),
        ),
      ),
    );

    expect(find.text('Restart after queue'), findsOneWidget);
    expect(find.text('Daemon exits when idle'), findsOneWidget);
    expect(find.text('Nothing queued'), findsNothing);
  });
}
