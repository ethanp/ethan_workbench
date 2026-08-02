import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../projects/deployable_project.dart';
import '../projects/deploy_source_hasher.dart';
import '../projects/project_scanner.dart';
import '../sync/deploy_ledger.dart';
import 'deploy_checklist.dart';
import 'deploy_errors.dart';
import 'deploy_job.dart';
import 'deploy_platform.dart';
import 'deploy_run_record.dart';
import 'ruby_deploy_executor.dart';

/// Owns the single active deploy job and project catalog lookup.
class DeployService {
  DeployService({
    required this.flutterRoots,
    required this.deployRbPath,
    DeployScriptRunner? scriptRunner,
    this._ledger,
  }) : _scriptRunner = scriptRunner ?? DeployScriptRunner();

  final List<String> flutterRoots;
  final String deployRbPath;
  final DeployScriptRunner _scriptRunner;
  DeployLedger? _ledger;

  DeployJob? _activeJob;
  final _jobUpdatedController = StreamController<DeployJob>.broadcast();
  final _logListeners = <String, Set<StreamController<String>>>{};
  String _logLineBuffer = '';

  DeployJob? get activeJob => _activeJob;
  Stream<DeployJob> get jobUpdates => _jobUpdatedController.stream;

  void attachLedger(DeployLedger? ledger) {
    _ledger = ledger;
  }

  Future<List<DeployRunRecord>> listRecentRuns({int limit = 100}) async {
    final ledger = _ledger;
    if (ledger == null) return const [];
    return ledger.listRecentRuns(limit: limit);
  }

  Future<List<DeployableProject>> listProjects() async {
    final projects = await ProjectCatalog(
      flutterRoots: flutterRoots,
    ).listDeployableProjects();
    return _enrichWithLedger(projects);
  }

  /// Recomputes deploy.rb source hashes for every project/platform.
  Future<List<DeployableProject>> evaluateSourceChanges() async {
    final projects = await listProjects();
    final evaluated = <DeployableProject>[];
    for (final project in projects) {
      evaluated.add(
        project.copyWith(
          sourceStatus: await DeploySourceHasher.statusesFor(
            projectPath: project.path,
            platforms: project.platforms,
          ),
        ),
      );
    }
    evaluated.sort((left, right) {
      final leftChanged = left.hasChangedSources ? 0 : 1;
      final rightChanged = right.hasChangedSources ? 0 : 1;
      if (leftChanged != rightChanged) {
        return leftChanged.compareTo(rightChanged);
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return evaluated;
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
    required DeployPlatform platform,
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
    if (!project.supports(platform)) {
      throw UnsupportedDeployPlatform(
        projectName: project.name,
        platformLabel: platform.label,
      );
    }

    if (!await File(deployRbPath).exists()) {
      throw DeployScriptMissing(deployRbPath);
    }

    final job = DeployJob(
      jobId: _newJobId(),
      projectId: project.projectId,
      projectName: project.name,
      platform: platform,
      force: force,
      status: DeployJobStatus.queued,
      log: '',
      createdAt: DateTime.now(),
      checklist: DeployChecklist.planned(platform: platform, force: force),
    );
    _activeJob = job;
    _logLineBuffer = '';
    _emitJob(job);
    unawaited(_ledger?.recordRunStarted(job));
    unawaited(_runJob(job, project));
    return job;
  }

  Future<DeployJob> fetchJob(String jobId) async {
    final job = _activeJob;
    if (job == null || job.jobId != jobId) {
      throw DeployJobNotFound(jobId);
    }
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
    final startedAt = DateTime.now();
    _updateJob(
      job.copyWith(
        status: DeployJobStatus.running,
        checklist: DeployChecklist.activateFirst(job.checklist, at: startedAt),
      ),
    );
    _appendLog(
      'Starting ${job.platform.label} deploy for ${project.name}\n'
      'cwd: ${project.path}\n'
      'ruby $deployRbPath ${job.platform.scriptArgument}'
      '${job.force ? ' --force' : ''}\n\n',
    );

    try {
      final exitCode = await _scriptRunner.runDeploy(
        deployRbPath: deployRbPath,
        projectPath: project.path,
        platform: job.platform,
        force: job.force,
        onOutput: _appendLog,
      );
      _flushLogBuffer();

      final succeeded = exitCode == 0;
      _appendLog(
        succeeded
            ? '\n✓ Deploy finished successfully\n'
            : '\n✗ Deploy failed (exit $exitCode)\n',
      );
      final finishedAt = DateTime.now();
      final currentJob = _activeJob!;
      final finishedJob = currentJob.copyWith(
        status: succeeded ? DeployJobStatus.succeeded : DeployJobStatus.failed,
        finishedAt: finishedAt,
        exitCode: exitCode,
        checklist: succeeded
            ? DeployChecklist.applyPhase(
                currentJob.checklist,
                'done',
                at: finishedAt,
              )
            : currentJob.checklist,
      );
      _updateJob(finishedJob);
      await _recordFinished(finishedJob, projectPath: project.path);
    } catch (error, stackTrace) {
      _flushLogBuffer();
      _appendLog('\n✗ Deploy crashed: $error\n$stackTrace\n');
      final failedJob = _activeJob!.copyWith(
        status: DeployJobStatus.failed,
        finishedAt: DateTime.now(),
        exitCode: -1,
      );
      _updateJob(failedJob);
      await _recordFinished(failedJob, projectPath: project.path);
    }
  }

  Future<void> _recordFinished(
    DeployJob job, {
    required String projectPath,
  }) async {
    final ledger = _ledger;
    if (ledger == null) return;
    String? sourceHash;
    if (job.status == DeployJobStatus.succeeded) {
      final hashFile = File('$projectPath/.deploy_${job.platform.name}_hash');
      if (await hashFile.exists()) {
        sourceHash = (await hashFile.readAsString()).trim();
      }
    }
    await ledger.recordRunFinished(job, sourceHash: sourceHash);
  }

  Future<List<DeployableProject>> _enrichWithLedger(
    List<DeployableProject> projects,
  ) async {
    final ledger = _ledger;
    if (ledger == null) return projects;
    final enriched = <DeployableProject>[];
    for (final project in projects) {
      final ledgerTimes = await ledger.lastDeployedAtFor(project.projectId);
      if (ledgerTimes.isEmpty) {
        enriched.add(project);
        continue;
      }
      final merged = <DeployPlatform, DateTime?>{...project.lastDeployedAt};
      for (final entry in ledgerTimes.entries) {
        merged[entry.key] = entry.value ?? merged[entry.key];
      }
      enriched.add(project.copyWith(lastDeployedAt: merged));
    }
    return enriched;
  }

  void _appendLog(String chunk) {
    _logLineBuffer += chunk;
    final splitLines = _logLineBuffer.split('\n');
    _logLineBuffer = splitLines.removeLast();
    for (final line in splitLines) {
      _consumeLogLine(line);
    }
  }

  void _flushLogBuffer() {
    if (_logLineBuffer.isEmpty) return;
    _consumeLogLine(_logLineBuffer);
    _logLineBuffer = '';
  }

  void _consumeLogLine(String line) {
    if (line.startsWith(DeployChecklist.phasePrefix)) {
      final phaseId = line.substring(DeployChecklist.phasePrefix.length).trim();
      if (phaseId.isEmpty) return;
      final currentJob = _activeJob;
      if (currentJob == null) return;
      _updateJob(
        currentJob.copyWith(
          checklist: DeployChecklist.applyPhase(
            currentJob.checklist,
            phaseId,
            at: DateTime.now(),
          ),
        ),
      );
      return;
    }
    _emitLogChunk('$line\n');
  }

  void _emitLogChunk(String chunk) {
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
