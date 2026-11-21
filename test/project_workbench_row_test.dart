import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/projects/project_workbench_row.dart';
import 'package:ethan_workbench/projects/workbench_project.dart';
import 'package:ethan_workbench/run/local_run_state.dart';
import 'package:ethan_workbench/ui/widgets/e_action_cluster.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  const project = WorkbenchProject(
    projectId: 'spend_trends',
    name: 'spend_trends',
    path: '/tmp/spend_trends',
    platforms: {DeployPlatform.macos, DeployPlatform.ios},
  );

  Future<List<Offset>> clusterOriginsAt(
    WidgetTester tester,
    double width,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(Size(width, 600));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ProjectWorkbenchRow(
              project: project,
              platforms: const [DeployPlatform.macos, DeployPlatform.ios],
              runStateFor: (_) => LocalRunState.idle,
              canRunLocally: true,
              showLineAge: true,
              onLineAge: () {},
              onDeploy: (_) {},
              onRun: (_) {},
              onStopRun: (_) {},
              onOpenOngoingDeploy: () {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    return tester
        .widgetList<EActionCluster>(find.byType(EActionCluster))
        .map((cluster) => tester.getTopLeft(find.byWidget(cluster)))
        .toList();
  }

  testWidgets('platform clusters sit side by side while they keep labels', (
    tester,
  ) async {
    final List<Offset> origins = await clusterOriginsAt(tester, 1300);
    expect(origins, hasLength(2));
    expect(origins[0].dy, origins[1].dy);
    expect(origins[1].dx, greaterThan(origins[0].dx));
  });

  testWidgets('platform clusters stack once side by side would go icon-only', (
    tester,
  ) async {
    final List<Offset> origins = await clusterOriginsAt(tester, 620);
    expect(origins, hasLength(2));
    expect(origins[0].dx, origins[1].dx);
    expect(origins[1].dy, greaterThan(origins[0].dy));
  });
}
