import 'package:ethan_workbench/deploy/deploy_job.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/deploy/deploy_run_record.dart';
import 'package:ethan_workbench/deploy/deploy_trigger.dart';
import 'package:ethan_workbench/projects/projects_catalog.dart';
import 'package:ethan_workbench/projects/source_changes_progress.dart';
import 'package:ethan_workbench/projects/workbench_project.dart';
import 'package:flutter_test/flutter_test.dart';

class _CatalogTestScenario(final List<WorkbenchProject> suppliedProjects) {
  DeployTrigger get triggerWithoutLineAge => _trigger(showLineAge: false);

  DeployTrigger get triggerWithLineAge => _trigger(showLineAge: true);

  DeployTrigger _trigger({required bool showLineAge}) {
    return DeployTrigger(
      showLineAgeAnalysis: showLineAge,
      listProjects: () async => suppliedProjects,
      evaluateSourceChanges: ({
        void Function(SourceChangesProgress progress)? onProgress,
      }) async => suppliedProjects,
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
  }
}

void main() {
  test('empty platforms survive JSON roundtrip', () {
    const library = WorkbenchProject(
      projectId: 'ethan_utils',
      name: 'ethan_utils',
      path: '/tmp/ethan_utils',
      platforms: {},
    );

    final restored = WorkbenchProject.fromJson(library.toJson());

    expect(restored.platforms, isEmpty);
    expect(restored.isDeployable, isFalse);
  });

  test('missing legacy platforms field defaults to iOS', () {
    final restored = WorkbenchProject.fromJson({
      'projectId': 'legacy_app',
      'name': 'legacy_app',
      'path': '/tmp/legacy_app',
    });

    expect(restored.platforms, {DeployPlatform.ios});
    expect(restored.isDeployable, isTrue);
  });

  test('successful deploy updates the selected platform', () {
    final justFinished = DateTime(2026, 8, 29, 13, 20);
    final updated =
        WorkbenchProject(
          projectId: 'health_notes',
          name: 'health_notes',
          path: '/tmp/health_notes',
          platforms: const {DeployPlatform.ios, DeployPlatform.macos},
          sourceStatus: const {
            DeployPlatform.ios: DeploySourceStatus.changed,
            DeployPlatform.macos: DeploySourceStatus.unchanged,
          },
          lastDeployedAt: {DeployPlatform.ios: DateTime(2026, 8, 24)},
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

  test(
    'desktop catalog includes libraries and gives them no platforms',
    () async {
      const library = WorkbenchProject(
        projectId: 'ethan_utils',
        name: 'ethan_utils',
        path: '/tmp/ethan_utils',
        platforms: {},
      );
      final catalog = ProjectsCatalog(
        trigger: _CatalogTestScenario(const [library]).triggerWithLineAge,
      );

      await catalog.load(evaluateChanges: false);

      expect(catalog.projects, const [library]);
      expect(catalog.platformsFor(library), isEmpty);
      catalog.dispose();
    },
  );

  test('client catalog hides libraries without Line age', () async {
    const library = WorkbenchProject(
      projectId: 'ethan_utils',
      name: 'ethan_utils',
      path: '/tmp/ethan_utils',
      platforms: {},
    );
    const app = WorkbenchProject(
      projectId: 'health_notes',
      name: 'health_notes',
      path: '/tmp/health_notes',
      platforms: {DeployPlatform.ios},
    );
    final catalog = ProjectsCatalog(
      trigger: _CatalogTestScenario(const [library, app]).triggerWithoutLineAge,
    );

    await catalog.load(evaluateChanges: false);

    expect(catalog.projects, const [app]);
    expect(catalog.platformsFor(app), const [
      DeployPlatform.ios,
      DeployPlatform.macos,
    ]);
    catalog.dispose();
  });
}
