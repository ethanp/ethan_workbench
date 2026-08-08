import 'dart:async';
import 'dart:io';

import '../projects/deployable_project.dart';
import '../run/os_process_tree.dart';
import 'deploy_checklist.dart';
import 'deploy_console.dart';
import 'deploy_job.dart';
import 'deploy_log_file_follow.dart';
import 'deploy_session_persistence.dart';
import 'deploy_wait_queue.dart';
import 'ruby_deploy_executor.dart';

/// One active deploy run: script process, session checkpoint, finish/fail.
class ActiveDeploySlot {
  ActiveDeploySlot({
    required this.deployRbPath,
    required this._scriptRunner,
    required this._console,
    required this._waitQueue,
    required this.onJobUpdated,
    required this.onPromoteNext,
    this._persistence,
    this._isPidAlive,
  });

  final String deployRbPath;
  final DeployScriptRunner _scriptRunner;
  final DeployConsole _console;
  final DeployWaitQueue _waitQueue;
  final void Function(DeployJob job) onJobUpdated;
  final Future<void> Function() onPromoteNext;
  final DeploySessionPersistence? _persistence;
  final Future<bool> Function(int pid)? _isPidAlive;
  final _pidWatch = PidLivenessWatch();

  int? _pid;
  String? _projectPath;
  String? _exitCodePath;
  String? _logPath;
  DeployLogFileFollow? _logFollow;

  DeployJob? get job => _console.job;
  String? get projectPath => _projectPath ?? _console.projectPath;
  int? get pid => _pid;
  String? get exitCodePath => _exitCodePath;
  String? get logPath => _logPath;

  bool get hasActiveRunner {
    final active = job;
    return active != null && active.status.isActiveRunner;
  }

  /// Start the ruby deploy for [job] and drive it to a terminal status.
  Future<void> start(DeployJob job, DeployableProject project) async {
    _projectPath = project.path;
    final startedAt = DateTime.now();
    _console.applyJob(
      job.copyWith(
        status: DeployJobStatus.running,
        checklist: DeployChecklist.activateFirst(job.checklist, at: startedAt),
      ),
    );
    unawaited(checkpoint());

    _console.append(
      'Starting ${job.platform.label} deploy for ${project.name}\n'
      'cwd: ${project.path}\n'
      'ruby $deployRbPath ${job.platform.scriptArgument}'
      '${job.force ? ' --force' : ''}\n\n',
    );

    final persistence = _persistence;
    final exitCodePath = persistence == null
        ? null
        : await persistence.exitCodePathFor(job.jobId);
    final logPath = persistence == null
        ? null
        : await persistence.logPathFor(job.jobId);
    _exitCodePath = exitCodePath;
    _logPath = logPath;

    try {
      final exitCode = await _scriptRunner.runDeploy(
        deployRbPath: deployRbPath,
        projectPath: project.path,
        platform: job.platform,
        force: job.force,
        onOutput: _console.append,
        exitCodePath: exitCodePath,
        logPath: logPath,
        onStarted: (pid) {
          _pid = pid;
          unawaited(checkpoint());
        },
      );
      await finish(exitCode: exitCode);
    } catch (error, stackTrace) {
      _console.flush();
      _console.append('\n✗ Deploy crashed: $error\n$stackTrace\n');
      await _completeTerminal(
        succeeded: false,
        exitCode: -1,
        projectPath: project.path,
      );
    }
  }

  /// Adopt a process still running after workbench restart; resume log follow.
  Future<void> adoptReclaimed({
    required DeployJob job,
    required String projectPath,
    required String exitCodePath,
    required int pid,
    String? logPath,
  }) async {
    _projectPath = projectPath;
    _exitCodePath = exitCodePath;
    _logPath = logPath;
    _pid = pid;

    var mergedLog = job.log;
    if (logPath != null) {
      final logFile = File(logPath);
      if (await logFile.exists()) {
        mergedLog = mergeDeployLogWithFile(
          mergedLog,
          await logFile.readAsString(),
        );
      }
    }

    final reclaimed = job.copyWith(
      status: DeployJobStatus.running,
      log:
          '$mergedLog\n'
          'Reclaimed deploy after workbench restart (pid $pid). '
          'Resuming live log…\n',
    );
    _console.seed(reclaimed, projectPath: projectPath);
    unawaited(checkpoint());
    await _startLogFollow(logPath);
    _pidWatch.watch(pid, onDead: () => _onReclaimedPidDead(pid));
  }

  /// Process already exited when reclaiming after restart.
  Future<void> finishAfterRestartExit({
    required DeployJob job,
    required String projectPath,
    required int exitCode,
    String? logPath,
  }) async {
    _projectPath = projectPath;
    _logPath = logPath;
    var mergedLog = job.log;
    if (logPath != null) {
      final logFile = File(logPath);
      if (await logFile.exists()) {
        mergedLog = mergeDeployLogWithFile(
          mergedLog,
          await logFile.readAsString(),
        );
      }
    }
    final resumed = job.copyWith(
      status: DeployJobStatus.running,
      log:
          '$mergedLog\n'
          'Workbench restarted after deploy process exited.\n',
    );
    _console.applyJob(resumed);
    onJobUpdated(resumed);
    await finish(exitCode: exitCode);
  }

  Future<void> failInterrupted({
    required DeployJob job,
    required String projectPath,
    required String message,
  }) async {
    _projectPath = projectPath;
    final finishedAt = DateTime.now();
    final failed = job.copyWith(
      status: DeployJobStatus.failed,
      finishedAt: finishedAt,
      exitCode: -1,
      log: '${job.log}\n$message',
      checklist: DeployChecklist.applyPhase(
        job.checklist,
        'failed',
        at: finishedAt,
      ),
    );
    _console.applyJob(failed);
    await clearSession();
    unawaited(_console.finalize(failed));
    await _console.recordFinished(failed, projectPath: projectPath);
    await onPromoteNext();
  }

  Future<void> finish({required int exitCode}) async {
    final path = _projectPath;
    if (path == null) return;
    await _completeTerminal(
      succeeded: exitCode == 0,
      exitCode: exitCode,
      projectPath: path,
    );
  }

  Future<void> checkpoint() async {
    final persistence = _persistence;
    final activeJob = job;
    final projectPath = _projectPath;
    final exitCodePath = _exitCodePath;
    if (persistence == null ||
        activeJob == null ||
        activeJob.status.isTerminal ||
        projectPath == null ||
        exitCodePath == null) {
      return;
    }
    await persistence.write(
      DeploySessionRecord(
        activeJob: _jobForPersistence(activeJob),
        projectPath: projectPath,
        exitCodePath: exitCodePath,
        logPath: _logPath,
        pid: _pid,
        waiting: _waitQueue.jobs,
      ),
    );
  }

  Future<void> clearSession() async {
    _pidWatch.cancel();
    await _stopLogFollow();
    final exitCodePath = _exitCodePath;
    final logPath = _logPath;
    _pid = null;
    _exitCodePath = null;
    _logPath = null;
    final persistence = _persistence;
    if (persistence == null) return;
    await persistence.clear(exitCodePath: exitCodePath, logPath: logPath);
  }

  void clearProcessHandles() {
    _pid = null;
    _exitCodePath = null;
    _logPath = null;
    _projectPath = null;
  }

  Future<bool> pidIsAlive(int pid) {
    final override = _isPidAlive;
    if (override != null) return override(pid);
    return pid.asOsProcessTree.isAlive;
  }

  Future<int?> readExitCode(String exitCodePath) async {
    final exitFile = File(exitCodePath);
    if (!await exitFile.exists()) return null;
    return int.tryParse((await exitFile.readAsString()).trim());
  }

  Future<void> dispose() async {
    _pidWatch.cancel();
    await _stopLogFollow();
  }

  Future<void> _startLogFollow(String? logPath) async {
    await _stopLogFollow();
    if (logPath == null) return;
    final logFile = File(logPath);
    final startOffset = await logFile.exists() ? await logFile.length() : 0;
    final follow = DeployLogFileFollow(
      logPath: logPath,
      onChunk: _console.append,
      startOffset: startOffset,
    );
    _logFollow = follow;
    await follow.start();
  }

  Future<void> _stopLogFollow() async {
    final follow = _logFollow;
    _logFollow = null;
    await follow?.stop();
  }

  Future<void> _onReclaimedPidDead(int pid) async {
    if (_pid != pid) return;
    final projectPath = _projectPath;
    final exitCodePath = _exitCodePath;
    if (projectPath == null) return;
    await _stopLogFollow();
    final exitCode = exitCodePath == null
        ? -1
        : await readExitCode(exitCodePath) ?? -1;
    await finish(exitCode: exitCode);
  }

  Future<void> _completeTerminal({
    required bool succeeded,
    required int exitCode,
    required String projectPath,
  }) async {
    await _stopLogFollow();
    _console.flush();
    _console.append(
      succeeded
          ? '\n✓ Deploy finished successfully\n'
          : '\n✗ Deploy failed (exit $exitCode)\n',
    );
    final currentJob = job!;
    final finishedAt = DateTime.now();
    final finishedJob = currentJob.copyWith(
      status: succeeded ? DeployJobStatus.succeeded : DeployJobStatus.failed,
      finishedAt: finishedAt,
      exitCode: exitCode,
      checklist: DeployChecklist.applyPhase(
        currentJob.checklist,
        succeeded ? 'done' : 'failed',
        at: finishedAt,
      ),
    );
    _console.applyJob(finishedJob);
    await clearSession();
    unawaited(_console.finalize(finishedJob));
    await _console.recordFinished(finishedJob, projectPath: projectPath);
    await onPromoteNext();
  }

  DeployJob _jobForPersistence(DeployJob job) {
    const maxLogChars = 100000;
    if (job.log.length <= maxLogChars) return job;
    return job.copyWith(
      log: '…(truncated)\n${job.log.substring(job.log.length - maxLogChars)}',
    );
  }
}
