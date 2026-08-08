import 'dart:async';

import 'package:ethan_workbench/deploy/deploy_errors.dart';
import 'package:ethan_workbench/deploy/deploy_job.dart';
import 'package:ethan_workbench/deploy/deploy_pipeline.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/deploy/ruby_deploy_executor.dart';
import 'package:ethan_workbench/projects/deployable_project.dart';
import 'package:flutter_test/flutter_test.dart';

class _ControllableScriptRunner extends DeployScriptRunner {
  final _starts = <Completer<int>>[];

  int get startedCount => _starts.length;

  void completeLatest({int exitCode = 0}) {
    _starts.last.complete(exitCode);
  }

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
    onStarted?.call(9000 + _starts.length);
    onOutput('fake deploy\n');
    return completer.future;
  }
}

DeployableProject _project(String id, {String? name}) {
  return DeployableProject(
    projectId: id,
    name: name ?? id,
    path: '/tmp/$id',
    platforms: {DeployPlatform.macos, DeployPlatform.ios},
  );
}

void main() {
  late _ControllableScriptRunner scriptRunner;
  late Map<String, DeployableProject> projects;
  late DeployPipeline pipeline;

  setUp(() {
    scriptRunner = _ControllableScriptRunner();
    projects = {
      'a': _project('a', name: 'alpha'),
      'b': _project('b', name: 'beta'),
      'c': _project('c', name: 'gamma'),
    };
    pipeline = DeployPipeline(
      flutterRoots: const [],
      deployRbPath: '/tmp/deploy.rb',
      scriptRunner: scriptRunner,
      resolveProject: (id) async => projects[id],
      deployScriptExists: () async => true,
    );
  });

  tearDown(() async {
    await pipeline.dispose();
  });

  test('second start enqueues while first is running', () async {
    final first = await pipeline.startDeploy(
      projectId: 'a',
      platform: DeployPlatform.macos,
    );
    expect(first.status, DeployJobStatus.queued);
    await Future<void>.delayed(Duration.zero);
    expect(pipeline.activeJob?.status, DeployJobStatus.running);
    expect(scriptRunner.startedCount, 1);

    final second = await pipeline.startDeploy(
      projectId: 'b',
      platform: DeployPlatform.ios,
    );
    expect(second.status, DeployJobStatus.waiting);
    expect(pipeline.waitingQueue, hasLength(1));
    expect(pipeline.waitingQueue.single.projectId, 'b');
  });

  test('finish promotes next waiting job', () async {
    await pipeline.startDeploy(
      projectId: 'a',
      platform: DeployPlatform.macos,
    );
    await Future<void>.delayed(Duration.zero);
    await pipeline.startDeploy(
      projectId: 'b',
      platform: DeployPlatform.ios,
    );
    expect(pipeline.waitingQueue, hasLength(1));

    scriptRunner.completeLatest();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(pipeline.waitingQueue, isEmpty);
    expect(pipeline.activeJob?.projectId, 'b');
    expect(pipeline.activeJob?.status.isActiveRunner, isTrue);
    expect(scriptRunner.startedCount, 2);
  });

  test('cancel removes waiting job', () async {
    await pipeline.startDeploy(
      projectId: 'a',
      platform: DeployPlatform.macos,
    );
    await Future<void>.delayed(Duration.zero);
    final waiting = await pipeline.startDeploy(
      projectId: 'b',
      platform: DeployPlatform.ios,
    );
    expect(pipeline.cancelWaiting(waiting.jobId), isTrue);
    expect(pipeline.waitingQueue, isEmpty);
    expect(pipeline.cancelWaiting(waiting.jobId), isFalse);
  });

  test('duplicate waiting throws DeployAlreadyQueued', () async {
    await pipeline.startDeploy(
      projectId: 'a',
      platform: DeployPlatform.macos,
    );
    await Future<void>.delayed(Duration.zero);
    await pipeline.startDeploy(
      projectId: 'b',
      platform: DeployPlatform.ios,
    );
    expect(
      () => pipeline.startDeploy(
        projectId: 'b',
        platform: DeployPlatform.ios,
      ),
      throwsA(isA<DeployAlreadyQueued>()),
    );
  });

  test('same active project+platform returns the running job', () async {
    final first = await pipeline.startDeploy(
      projectId: 'a',
      platform: DeployPlatform.macos,
    );
    await Future<void>.delayed(Duration.zero);
    final again = await pipeline.startDeploy(
      projectId: 'a',
      platform: DeployPlatform.macos,
    );
    expect(again.jobId, first.jobId);
    expect(pipeline.waitingQueue, isEmpty);
  });
}
