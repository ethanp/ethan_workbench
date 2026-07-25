import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../api/models.dart';
import 'agent_config.dart';
import 'project_scanner.dart';

class DeployJobRunner {
  DeployJobRunner({required this._config});

  final AgentConfig _config;
  DeployJob? _activeJob;
  Process? _activeProcess;
  final _jobUpdatedController = StreamController<DeployJob>.broadcast();
  final _logListeners = <String, Set<StreamController<String>>>{};

  AgentConfig get config => _config;
  DeployJob? get activeJob => _activeJob;
  Stream<DeployJob> get jobUpdates => _jobUpdatedController.stream;

  Future<List<DeployableProject>> listProjects() {
    return ProjectScanner(flutterRoots: _config.flutterRoots).scan();
  }

  Future<DeployableProject?> findProject(String projectId) async {
    final projects = await listProjects();
    for (final project in projects) {
      if (project.projectId == projectId) return project;
    }
    return null;
  }

  Future<DeployJob> startDeploy({
    required String projectId,
    bool force = false,
  }) async {
    if (_activeJob != null && !_activeJob!.status.isTerminal) {
      throw StateError('A deploy is already running');
    }

    final project = await findProject(projectId);
    if (project == null) {
      throw ArgumentError('Unknown project: $projectId');
    }

    final deployRbFile = File(_config.deployRbPath);
    if (!await deployRbFile.exists()) {
      throw StateError('deploy.rb not found at ${_config.deployRbPath}');
    }

    final job = DeployJob(
      jobId: _newJobId(),
      projectId: project.projectId,
      projectName: project.name,
      force: force,
      status: DeployJobStatus.queued,
      log: '',
      createdAt: DateTime.now(),
    );
    _activeJob = job;
    _emitJob(job);
    unawaited(_runJob(job, project));
    return job;
  }

  Stream<String> watchLog(String jobId) {
    final controller = StreamController<String>();
    final listeners = _logListeners.putIfAbsent(jobId, () => {});
    listeners.add(controller);

    final currentJob = _activeJob;
    if (currentJob != null &&
        currentJob.jobId == jobId &&
        currentJob.log.isNotEmpty) {
      controller.add(currentJob.log);
    }

    controller.onCancel = () {
      listeners.remove(controller);
      if (listeners.isEmpty) {
        _logListeners.remove(jobId);
      }
    };
    return controller.stream;
  }

  Future<void> dispose() async {
    _activeProcess?.kill();
    await _jobUpdatedController.close();
    for (final listeners in _logListeners.values) {
      for (final controller in listeners) {
        await controller.close();
      }
    }
    _logListeners.clear();
  }

  Future<void> _runJob(DeployJob job, DeployableProject project) async {
    _updateJob(job.copyWith(status: DeployJobStatus.running));
    _appendLog(
      'Starting deploy for ${project.name}\n'
      'cwd: ${project.path}\n'
      'ruby ${_config.deployRbPath} ios${job.force ? ' --force' : ''}\n\n',
    );

    try {
      final arguments = [_config.deployRbPath, 'ios'];
      if (job.force) arguments.add('--force');

      final process = await Process.start(
        'ruby',
        arguments,
        workingDirectory: project.path,
        environment: {
          ...Platform.environment,
          'PYTHONUNBUFFERED': '1',
        },
        runInShell: false,
      );
      _activeProcess = process;

      final stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .listen(_appendLog);
      final stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .listen(_appendLog);

      final exitCode = await process.exitCode;
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      _activeProcess = null;

      final succeeded = exitCode == 0;
      _appendLog(
        succeeded
            ? '\n✓ Deploy finished successfully\n'
            : '\n✗ Deploy failed (exit $exitCode)\n',
      );
      _updateJob(
        _activeJob!.copyWith(
          status:
              succeeded ? DeployJobStatus.succeeded : DeployJobStatus.failed,
          finishedAt: DateTime.now(),
          exitCode: exitCode,
        ),
      );
    } catch (error, stackTrace) {
      _activeProcess = null;
      _appendLog('\n✗ Deploy crashed: $error\n$stackTrace\n');
      _updateJob(
        _activeJob!.copyWith(
          status: DeployJobStatus.failed,
          finishedAt: DateTime.now(),
          exitCode: -1,
        ),
      );
    }
  }

  void _appendLog(String chunk) {
    final currentJob = _activeJob;
    if (currentJob == null) return;
    final updatedJob = currentJob.copyWith(log: currentJob.log + chunk);
    _activeJob = updatedJob;
    _emitJob(updatedJob);
    final listeners = _logListeners[currentJob.jobId];
    if (listeners == null) return;
    for (final controller in listeners) {
      if (!controller.isClosed) controller.add(chunk);
    }
  }

  void _updateJob(DeployJob job) {
    _activeJob = job;
    _emitJob(job);
  }

  void _emitJob(DeployJob job) {
    if (!_jobUpdatedController.isClosed) {
      _jobUpdatedController.add(job);
    }
  }

  String _newJobId() {
    final random = Random();
    final suffix = List.generate(
      6,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return '${DateTime.now().millisecondsSinceEpoch}-$suffix';
  }
}
