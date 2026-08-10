import 'dart:async';
import 'dart:io';

import '../projects/deployable_project.dart';
import '../projects/source_changes_progress.dart';
import '../sync/deploy_ledger.dart';
import 'active_deploy_slot.dart';
import 'deploy_checklist.dart';
import 'deploy_console.dart';
import 'deploy_errors.dart';
import 'deploy_job.dart';
import 'deploy_platform.dart';
import 'deploy_project_directory.dart';
import 'deploy_run_record.dart';
import 'deploy_session_persistence.dart';
import 'deploy_wait_queue.dart';
import 'ruby_deploy_executor.dart';

/// Mac deploy desk: accept/cancel/restore deploys and expose live job state.
///
/// Collaborators own the deep work — wait queue, console/log, project directory,
/// and the active run slot.
class DeployPipeline {
  DeployPipeline({
    required List<String> flutterRoots,
    required this.deployRbPath,
    DeployScriptRunner? scriptRunner,
    DeploySessionPersistence? persistence,
    Future<bool> Function(int pid)? isPidAlive,
    DeployLedger? ledger,
    Future<DeployableProject?> Function(String projectId)? resolveProject,
    this._deployScriptExists,
  }) : _projectDirectory = DeployProjectDirectory(
         flutterRoots: flutterRoots,
         resolveProject: resolveProject,
       ),
       _jobUpdatedController = StreamController<DeployJob>.broadcast() {
    _console = DeployConsole(onJobUpdated: _emitJob);
    _waitQueue = DeployWaitQueue(onQueueChanged: () {
      unawaited(_slot.checkpoint());
    });
    _slot = ActiveDeploySlot(
      deployRbPath: deployRbPath,
      scriptRunner: scriptRunner ?? DeployScriptRunner(),
      console: _console,
      waitQueue: _waitQueue,
      onJobUpdated: _emitJob,
      onPromoteNext: _promoteNextWaiting,
      persistence: persistence,
      isPidAlive: isPidAlive,
    );
    _persistence = persistence;
    if (ledger != null) attachLedger(ledger);
  }

  final String deployRbPath;
  final Future<bool> Function()? _deployScriptExists;
  final DeployProjectDirectory _projectDirectory;
  late final DeployConsole _console;
  late final DeployWaitQueue _waitQueue;
  late final ActiveDeploySlot _slot;
  DeploySessionPersistence? _persistence;
  DeployLedger? _ledger;
  final StreamController<DeployJob> _jobUpdatedController;

  DeployJob? get activeJob => _console.job;
  List<DeployJob> get waitingQueue => _waitQueue.jobs;
  Stream<DeployJob> get jobUpdates => _jobUpdatedController.stream;
  Stream<List<DeployJob>> get queueUpdates => _waitQueue.updates;

  void attachLedger(DeployLedger? ledger) {
    _ledger = ledger;
    _console.attachLedger(ledger);
    _projectDirectory.attachLedger(ledger);
  }

  /// Reclaim a deploy left running across workbench hot restart.
  Future<void> restorePersistedSession() async {
    final persistence = _persistence;
    if (persistence == null) return;
    if (_slot.hasActiveRunner) return;

    final record = await persistence.read();
    if (record == null) return;

    final persistedJob = record.activeJob;
    if (persistedJob.status.isTerminal) {
      await persistence.clear(
        exitCodePath: record.exitCodePath,
        logPath: record.logPath,
      );
      return;
    }

    _waitQueue.replaceAll(record.waiting);

    final pid = record.pid;
    if (pid == null) {
      await _slot.failInterrupted(
        job: persistedJob,
        projectPath: record.projectPath,
        message:
            'Deploy interrupted before the process started '
            '(workbench restarted).\n',
      );
      return;
    }

    final alive = await _slot.pidIsAlive(pid);
    if (!alive) {
      final exitCode = await _slot.readExitCode(record.exitCodePath) ?? -1;
      await _slot.finishAfterRestartExit(
        job: persistedJob,
        projectPath: record.projectPath,
        exitCode: exitCode,
        logPath: record.logPath,
      );
      return;
    }

    await _slot.adoptReclaimed(
      job: persistedJob,
      projectPath: record.projectPath,
      exitCodePath: record.exitCodePath,
      pid: pid,
      logPath: record.logPath,
    );
  }

  Future<List<DeployRunRecord>> listRecentRuns({int limit = 100}) async {
    final ledger = _ledger;
    if (ledger == null) return const [];
    return ledger.listRecentRuns(limit: limit);
  }

  Future<List<DeployableProject>> listProjects() =>
      _projectDirectory.listDeployable();

  Future<List<DeployableProject>> evaluateSourceChanges({
    void Function(SourceChangesProgress progress)? onProgress,
  }) {
    return _projectDirectory.evaluateSourceChanges(onProgress: onProgress);
  }

  Future<DeployableProject?> findProject(String projectId) =>
      _projectDirectory.find(projectId);

  Future<DeployJob> startDeploy({
    required String projectId,
    required DeployPlatform platform,
    bool force = false,
  }) async {
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

    final scriptExists = _deployScriptExists != null
        ? await _deployScriptExists()
        : await File(deployRbPath).exists();
    if (!scriptExists) {
      throw DeployScriptMissing(deployRbPath);
    }

    final running = activeJob;
    if (running != null && running.status.isActiveRunner) {
      if (running.projectId == projectId && running.platform == platform) {
        return running;
      }
      final alreadyQueued = _waitQueue.findSameTarget(
        projectId: projectId,
        platform: platform,
      );
      if (alreadyQueued != null) {
        throw DeployAlreadyQueued(alreadyQueued);
      }
      final waitingJob = DeployJob(
        jobId: DeployJob.newId(),
        projectId: project.projectId,
        projectName: project.name,
        platform: platform,
        force: force,
        status: DeployJobStatus.waiting,
        log: '',
        createdAt: DateTime.now(),
        checklist: DeployChecklist.planned(platform: platform, force: force),
      );
      _waitQueue.enqueue(waitingJob);
      return waitingJob;
    }

    final job = DeployJob(
      jobId: DeployJob.newId(),
      projectId: project.projectId,
      projectName: project.name,
      platform: platform,
      force: force,
      status: DeployJobStatus.queued,
      log: '',
      createdAt: DateTime.now(),
      checklist: DeployChecklist.planned(platform: platform, force: force),
    );
    _console.begin(job, projectPath: project.path);
    unawaited(_slot.start(job, project));
    return job;
  }

  /// Removes a waiting job. Returns false if [jobId] is not in the queue.
  bool cancelWaiting(String jobId) => _waitQueue.cancel(jobId);

  Future<DeployJob> fetchJob(String jobId) async {
    final active = activeJob;
    if (active != null && active.jobId == jobId) return active;
    final waiting = _waitQueue.jobById(jobId);
    if (waiting != null) return waiting;
    final fromLedger = await _ledger?.fetchJob(jobId);
    if (fromLedger != null) return fromLedger;
    throw DeployJobNotFound(jobId);
  }

  Stream<String> watchLog(String jobId) => _console.watch(jobId);

  Future<void> dispose() async {
    await _slot.dispose();
    await _jobUpdatedController.close();
    await _waitQueue.dispose();
    await _console.dispose();
  }

  Future<void> _promoteNextWaiting() async {
    _slot.clearProcessHandles();
    while (_waitQueue.isNotEmpty) {
      final next = _waitQueue.takeNext();
      if (next == null) break;
      final project = await findProject(next.projectId);
      if (project == null || !project.supports(next.platform)) {
        continue;
      }
      final starting = next.copyWith(
        status: DeployJobStatus.queued,
        checklist: DeployChecklist.planned(
          platform: next.platform,
          force: next.force,
        ),
      );
      _console.begin(starting, projectPath: project.path);
      unawaited(_slot.start(starting, project));
      return;
    }
    unawaited(_slot.clearSession());
  }

  void _emitJob(DeployJob job) {
    if (!_jobUpdatedController.isClosed) {
      _jobUpdatedController.add(job);
    }
  }
}
