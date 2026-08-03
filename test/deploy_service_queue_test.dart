import 'dart:async';

import 'package:ethan_workbench/deploy/deploy_errors.dart';
import 'package:ethan_workbench/deploy/deploy_job.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/deploy/deploy_service.dart';
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
  }) {
    final completer = Completer<int>();
    _starts.add(completer);
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
  late DeployService service;

  setUp(() {
    scriptRunner = _ControllableScriptRunner();
    projects = {
      'a': _project('a', name: 'alpha'),
      'b': _project('b', name: 'beta'),
      'c': _project('c', name: 'gamma'),
    };
    service = DeployService(
      flutterRoots: const [],
      deployRbPath: '/tmp/deploy.rb',
      scriptRunner: scriptRunner,
      resolveProject: (id) async => projects[id],
      deployScriptExists: () async => true,
    );
  });

  tearDown(() async {
    await service.dispose();
  });

  test('second start enqueues while first is running', () async {
    final first = await service.startDeploy(
      projectId: 'a',
      platform: DeployPlatform.macos,
    );
    expect(first.status, DeployJobStatus.queued);
    await Future<void>.delayed(Duration.zero);
    expect(service.activeJob?.status, DeployJobStatus.running);
    expect(scriptRunner.startedCount, 1);

    final second = await service.startDeploy(
      projectId: 'b',
      platform: DeployPlatform.ios,
    );
    expect(second.status, DeployJobStatus.waiting);
    expect(service.waitingQueue, hasLength(1));
    expect(service.waitingQueue.single.projectId, 'b');
  });

  test('finish promotes next waiting job', () async {
    await service.startDeploy(
      projectId: 'a',
      platform: DeployPlatform.macos,
    );
    await Future<void>.delayed(Duration.zero);
    await service.startDeploy(
      projectId: 'b',
      platform: DeployPlatform.ios,
    );
    expect(service.waitingQueue, hasLength(1));

    scriptRunner.completeLatest();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(service.waitingQueue, isEmpty);
    expect(service.activeJob?.projectId, 'b');
    expect(service.activeJob?.status.isActiveRunner, isTrue);
    expect(scriptRunner.startedCount, 2);
  });

  test('cancel removes waiting job', () async {
    await service.startDeploy(
      projectId: 'a',
      platform: DeployPlatform.macos,
    );
    await Future<void>.delayed(Duration.zero);
    final waiting = await service.startDeploy(
      projectId: 'b',
      platform: DeployPlatform.ios,
    );
    expect(service.cancelWaiting(waiting.jobId), isTrue);
    expect(service.waitingQueue, isEmpty);
    expect(service.cancelWaiting(waiting.jobId), isFalse);
  });

  test('duplicate waiting throws DeployAlreadyQueued', () async {
    await service.startDeploy(
      projectId: 'a',
      platform: DeployPlatform.macos,
    );
    await Future<void>.delayed(Duration.zero);
    await service.startDeploy(
      projectId: 'b',
      platform: DeployPlatform.ios,
    );
    expect(
      () => service.startDeploy(
        projectId: 'b',
        platform: DeployPlatform.ios,
      ),
      throwsA(isA<DeployAlreadyQueued>()),
    );
  });

  test('same active project+platform returns the running job', () async {
    final first = await service.startDeploy(
      projectId: 'a',
      platform: DeployPlatform.macos,
    );
    await Future<void>.delayed(Duration.zero);
    final again = await service.startDeploy(
      projectId: 'a',
      platform: DeployPlatform.macos,
    );
    expect(again.jobId, first.jobId);
    expect(service.waitingQueue, isEmpty);
  });
}
