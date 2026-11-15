import 'dart:io';

import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/projects/project_scanner.dart';
import 'package:ethan_workbench/projects/workbench_project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

class _PubspecProjectTree(final Directory root) {
  Future<void> addProject(
    String relativePath, {
    Set<DeployPlatform> platforms = const {},
  }) async {
    final projectDirectory = Directory(path.join(root.path, relativePath));
    await projectDirectory.create(recursive: true);
    await File(path.join(projectDirectory.path, 'pubspec.yaml'))
        .writeAsString('name: ${path.basename(relativePath)}\n');
    for (final platform in platforms) {
      await Directory(path.join(projectDirectory.path, platform.name)).create();
    }
  }
}

void main() {
  late Directory flutterRoot;
  late _PubspecProjectTree projectTree;

  setUp(() async {
    flutterRoot = await Directory.systemTemp.createTemp(
      'workbench_project_scanner_',
    );
    projectTree = _PubspecProjectTree(flutterRoot);
  });

  tearDown(() async {
    await flutterRoot.delete(recursive: true);
  });

  test('discovers libraries and deployable apps', () async {
    await projectTree.addProject('ethan_ui');
    await projectTree.addProject('ethan_sync');
    await projectTree.addProject('ethan_utils');
    await projectTree.addProject('viant_core');
    await projectTree.addProject(
      'health_notes',
      platforms: const {DeployPlatform.ios, DeployPlatform.macos},
    );

    final projects = await ProjectCatalog(
      flutterRoots: [flutterRoot.path],
      macBackupsRoot: path.join(flutterRoot.path, 'no_backups'),
    ).listProjects();

    expect(projects.map((project) => project.projectId), [
      'ethan_sync',
      'ethan_ui',
      'ethan_utils',
      'health_notes',
      'viant_core',
    ]);
    expect(
      projects
          .singleWhere((project) => project.projectId == 'health_notes')
          .platforms,
      const {DeployPlatform.ios, DeployPlatform.macos},
    );
    expect(
      projects
          .where((project) => project.projectId != 'health_notes')
          .every((project) => !project.isDeployable),
      isTrue,
    );
  });

  test('pubspec project is a boundary for nested examples', () async {
    await projectTree.addProject('ethan_ui');
    await projectTree.addProject(
      path.join('ethan_ui', 'example'),
      platforms: const {DeployPlatform.ios},
    );

    final projects = await ProjectCatalog(
      flutterRoots: [flutterRoot.path],
      macBackupsRoot: path.join(flutterRoot.path, 'no_backups'),
    ).listProjects();

    expect(projects.map((project) => project.projectId), ['ethan_ui']);
  });

  test('sync app projects carry the newest backup on this Mac', () async {
    await projectTree.addProject('ethan_ui');
    await projectTree.addProject(
      'viant/apps/viant_ios',
      platforms: const {DeployPlatform.ios},
    );
    await projectTree.addProject(
      'workouts',
      platforms: const {DeployPlatform.ios},
    );
    for (final syncApp in ['viant', 'workouts']) {
      await File(path.join(flutterRoot.path, syncApp, 'db', 'powersync.yaml'))
          .create(recursive: true);
    }
    final macBackupsRoot = path.join(flutterRoot.path, 'backups');
    final olderDump = File(
      path.join(macBackupsRoot, 'viant', 'viant_2026-11-14.dump'),
    );
    final newerDump = File(
      path.join(macBackupsRoot, 'viant', 'viant_2026-11-15.dump'),
    );
    final partialDump = File(
      path.join(macBackupsRoot, 'viant', 'viant_2026-11-16.dump.partial'),
    );
    for (final dump in [olderDump, newerDump, partialDump]) {
      await dump.create(recursive: true);
    }
    await olderDump.setLastModified(DateTime(2026, 11, 14, 3));
    await newerDump.setLastModified(DateTime(2026, 11, 15, 3));
    await partialDump.setLastModified(DateTime(2026, 11, 16, 3));

    final projects = await ProjectCatalog(
      flutterRoots: [flutterRoot.path],
      macBackupsRoot: macBackupsRoot,
    ).listProjects();
    WorkbenchProject projectWithId(String projectId) =>
        projects.singleWhere((project) => project.projectId == projectId);

    expect(projectWithId('ethan_ui').syncDatabaseBackup, isNull);
    expect(
      projectWithId('viant/apps/viant_ios').syncDatabaseBackup?.databaseName,
      'viant',
    );
    expect(
      projectWithId('viant/apps/viant_ios').syncDatabaseBackup?.lastBackupAt,
      DateTime(2026, 11, 15, 3),
    );
    expect(projectWithId('workouts').syncDatabaseBackup?.lastBackupAt, isNull);
    expect(projectWithId('workouts').syncDatabaseBackup?.isStale, isTrue);

    final viantFromJson = WorkbenchProject.fromJson(
      projectWithId('viant/apps/viant_ios').toJson(),
    );
    expect(
      viantFromJson.syncDatabaseBackup?.lastBackupAt?.toLocal(),
      DateTime(2026, 11, 15, 3),
    );
  });
}
