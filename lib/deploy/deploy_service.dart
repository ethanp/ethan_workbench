import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../projects/deployable_project.dart';
import '../projects/project_scanner.dart';
import 'deploy_errors.dart';
import 'deploy_job.dart';
import 'ruby_deploy_executor.dart';

/// Owns the single active deploy job and project catalog lookup.
class DeployService {
  DeployService({
    required this.flutterRoots,
    required this.deployRbPath,
    DeployScriptRunner? scriptRunner,
  }) : _scriptRunner = scriptRunner ?? DeployScriptRunner();

  final List<String> flutterRoots;
  final String deployRbPath;
  final DeployScriptRunner _scriptRunner;

  DeployJob? _activeJob;
  final _jobUpdatedController = StreamController<DeployJob>.broadcast();
  final _logListeners = <String, Set<StreamController<String>>>{};

  DeployJob? get activeJob => _activeJob;
  Stream<DeployJob> get jobUpdates => _jobUpdatedController.stream;

  Future<List<DeployableProject>> listProjects() {
    return ProjectCatalog(flutterRoots: flutterRoots).listDeployableProjects();
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
    final activeJob = _activeJob;
    if (activeJob != null && !activeJob.status.isTerminal) {
      throw DeployAlreadyRunning(
        projectName: activeJob.projectName,
        jobId: activeJob.jobId,
        statusName: activeJob.status.name,
      );
    }

    final project = await findProject(projectId);
    if (project == null) {
      throw UnknownProject(projectId);
    }

    if (!await File(deployRbPath).exists()) {
      throw DeployScriptMissing(deployRbPath);
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
      'ruby $deployRbPath ios${job.force ? ' --force' : ''}\n\n',
    );

    try {
      final exitCode = await _scriptRunner.runIosDeploy(
        deployRbPath: deployRbPath,
        projectPath: project.path,
        force: job.force,
        onOutput: _appendLog,
      );

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
