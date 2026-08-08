import 'dart:async';
import 'dart:io';

import 'package:ethan_workbench/deploy/deploy_job.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/deploy/deploy_pipeline.dart';
import 'package:ethan_workbench/deploy/deploy_session_persistence.dart';
import 'package:ethan_workbench/deploy/ruby_deploy_executor.dart';
import 'package:ethan_workbench/projects/deployable_project.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryPersistence extends DeploySessionPersistence {
  DeploySessionRecord? record;
  final deletedExitPaths = <String>[];

  @override
  Future<String> exitCodePathFor(String jobId) async =>
      '/tmp/deploy_exit_$jobId.txt';

  @override
  Future<String> logPathFor(String jobId) async =>
      '/tmp/deploy_log_$jobId.txt';

  @override
  Future<DeploySessionRecord?> read() async => record;

  @override
  Future<void> write(DeploySessionRecord next) async {
    record = next;
  }

  @override
  Future<void> clear({String? exitCodePath, String? logPath}) async {
    record = null;
    if (exitCodePath != null) deletedExitPaths.add(exitCodePath);
  }
}

class _ControllableScriptRunner extends DeployScriptRunner {
  final _starts = <Completer<int>>[];

  @override
  Future<int> runDeploy({
    required String deployRbPath,
    required String projectPath,
    required DeployPlatform platform,
    required bool force,
    required void Function(String chunk) onOutput,
    String? exitCodePath,
    String? logPath,
    void Function(int pid)? onStarted,
  }) {
    final completer = Completer<int>();
    _starts.add(completer);
    onStarted?.call(4242);
    onOutput('fake deploy\n');
    return completer.future;
  }
}

DeployableProject _project(String id) {
  return DeployableProject(
    projectId: id,
    name: id,
    path: '/tmp/$id',
    platforms: {DeployPlatform.macos},
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('deploy_restore_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('startDeploy checkpoints session with pid for reclaim', () async {
    final persistence = _MemoryPersistence();
    final scriptRunner = _ControllableScriptRunner();
    final pipeline = DeployPipeline(
      flutterRoots: const [],
      deployRbPath: '/tmp/deploy.rb',
      scriptRunner: scriptRunner,
      persistence: persistence,
      resolveProject: (id) async => _project(id),
      deployScriptExists: () async => true,
    );

    await pipeline.startDeploy(
      projectId: 'a',
      platform: DeployPlatform.macos,
    );
    await Future<void>.delayed(Duration.zero);

    expect(persistence.record, isNotNull);
    expect(persistence.record!.pid, 4242);
    expect(persistence.record!.activeJob.status, DeployJobStatus.running);
    expect(persistence.record!.projectPath, '/tmp/a');

    scriptRunner._starts.single.complete(0);
    await Future<void>.delayed(Duration.zero);
    expect(persistence.record, isNull);

    await pipeline.dispose();
  });

  test('restorePersistedSession reclaims live pid and finishes from exit file',
      () async {
    final exitFile = File('${tempDir.path}/exit.txt');
    final persistence = _MemoryPersistence();
    final job = DeployJob(
      jobId: 'job-1',
      projectId: 'a',
      projectName: 'a',
      platform: DeployPlatform.macos,
      force: false,
      status: DeployJobStatus.running,
      log: 'partial log\n',
      createdAt: DateTime(2026, 1, 1),
    );
    persistence.record = DeploySessionRecord(
      activeJob: job,
      projectPath: '/tmp/a',
      exitCodePath: exitFile.path,
      pid: 77,
      waiting: const [],
    );

    var alive = true;
    final pipeline = DeployPipeline(
      flutterRoots: const [],
      deployRbPath: '/tmp/deploy.rb',
      persistence: persistence,
      isPidAlive: (pid) async {
        expect(pid, 77);
        return alive;
      },
      resolveProject: (id) async => _project(id),
      deployScriptExists: () async => true,
    );

    await pipeline.restorePersistedSession();
    expect(pipeline.activeJob?.status, DeployJobStatus.running);
    expect(pipeline.activeJob?.log, contains('Reclaimed deploy'));
    expect(pipeline.activeJob?.log, contains('Resuming live log'));
    expect(pipeline.activeJob?.log, isNot(contains('paused')));

    await exitFile.writeAsString('0');
    alive = false;
    // PidLivenessWatch polls every 2s — drive finish directly via a second
    // restore-style death by completing through a short delay after flipping
    // alive is insufficient; call the public path by restoring again is wrong.
    // Instead: write exit file and invoke restore on a fresh service that sees
    // dead pid.
    await pipeline.dispose();

    final finishedPersistence = _MemoryPersistence()
      ..record = DeploySessionRecord(
        activeJob: job,
        projectPath: '/tmp/a',
        exitCodePath: exitFile.path,
        pid: 77,
      );
    final finishedPipeline = DeployPipeline(
      flutterRoots: const [],
      deployRbPath: '/tmp/deploy.rb',
      persistence: finishedPersistence,
      isPidAlive: (_) async => false,
      resolveProject: (id) async => _project(id),
      deployScriptExists: () async => true,
    );

    await finishedPipeline.restorePersistedSession();
    expect(finishedPipeline.activeJob?.status, DeployJobStatus.succeeded);
    expect(finishedPersistence.record, isNull);

    await finishedPipeline.dispose();
  });

  test('restorePersistedSession restores waiting queue', () async {
    final exitFile = File('${tempDir.path}/exit2.txt');
    await exitFile.writeAsString('0');
    final waiting = DeployJob(
      jobId: 'wait-1',
      projectId: 'b',
      projectName: 'b',
      platform: DeployPlatform.macos,
      force: false,
      status: DeployJobStatus.waiting,
      log: '',
      createdAt: DateTime(2026, 1, 1),
    );
    final persistence = _MemoryPersistence()
      ..record = DeploySessionRecord(
        activeJob: DeployJob(
          jobId: 'job-1',
          projectId: 'a',
          projectName: 'a',
          platform: DeployPlatform.macos,
          force: false,
          status: DeployJobStatus.running,
          log: '',
          createdAt: DateTime(2026, 1, 1),
        ),
        projectPath: '/tmp/a',
        exitCodePath: exitFile.path,
        pid: 88,
        waiting: [waiting],
      );

    final scriptRunner = _ControllableScriptRunner();
    final pipeline = DeployPipeline(
      flutterRoots: const [],
      deployRbPath: '/tmp/deploy.rb',
      scriptRunner: scriptRunner,
      persistence: persistence,
      isPidAlive: (_) async => false,
      resolveProject: (id) async => _project(id),
      deployScriptExists: () async => true,
    );

    await pipeline.restorePersistedSession();
    // Active a finished; b promoted and started.
    await Future<void>.delayed(Duration.zero);
    expect(pipeline.activeJob?.projectId, 'b');
    expect(pipeline.activeJob?.status.isActiveRunner, isTrue);
    expect(scriptRunner._starts, hasLength(1));

    scriptRunner._starts.single.complete(0);
    await Future<void>.delayed(Duration.zero);
    await pipeline.dispose();
  });
}
