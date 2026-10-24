import 'dart:convert';
import 'dart:io';

import 'package:ethan_workbench/cursor/workbench_cursor_dirs.dart';
import 'package:ethan_workbench/deploy/deploy_cursor_mirror.dart';
import 'package:ethan_workbench/deploy/deploy_job.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory fakePackageRoot;
  late Directory originalWorkingDirectory;

  setUp(() async {
    originalWorkingDirectory = Directory.current;
    fakePackageRoot = await Directory.systemTemp.createTemp('deploy_status_');
    File(
      path.join(fakePackageRoot.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: ethan_workbench\n');
    Directory.current = fakePackageRoot;
    WorkbenchCursorDirs.resetForTest();
    DeployCursorMirror.resetForTest();
  });

  tearDown(() async {
    DeployCursorMirror.resetForTest();
    Directory.current = originalWorkingDirectory;
    WorkbenchCursorDirs.resetForTest();
    if (await fakePackageRoot.exists()) {
      await fakePackageRoot.delete(recursive: true);
    }
  });

  test('status is written while updates keep arriving', () async {
    final started = DateTime.now();
    while (DateTime.now().difference(started) <
        const Duration(milliseconds: 400)) {
      DeployCursorMirror.scheduleStatus(
        _job(DeployJobStatus.running),
        projectPath: '/tmp/viant_ios',
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }

    final status = await _readStatus(fakePackageRoot);
    expect(status, isNotNull);
    expect(status!['status'], 'running');
  });

  test('a finished status is not overwritten by an earlier write', () async {
    DeployCursorMirror.scheduleStatus(
      _job(DeployJobStatus.running),
      projectPath: '/tmp/viant_ios',
    );
    await Future<void>.delayed(const Duration(milliseconds: 160));
    await DeployCursorMirror.finalize(
      _job(DeployJobStatus.succeeded),
      projectPath: '/tmp/viant_ios',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final status = await _readStatus(fakePackageRoot);
    expect(status?['status'], 'succeeded');
  });
}

DeployJob _job(DeployJobStatus status) {
  return DeployJob(
    jobId: 'job-1',
    projectId: 'viant/apps/viant_ios',
    projectName: 'viant_ios',
    platform: DeployPlatform.ios,
    force: false,
    status: status,
    log: '',
    createdAt: DateTime(2026, 10, 24, 10, 53),
  );
}

Future<Map<String, dynamic>?> _readStatus(Directory packageRoot) async {
  final statusFile = File(
    path.join(
      packageRoot.path,
      '.workbench',
      DeployCursorMirror.statusFileName,
    ),
  );
  if (!statusFile.existsSync()) return null;
  return jsonDecode(await statusFile.readAsString()) as Map<String, dynamic>;
}
