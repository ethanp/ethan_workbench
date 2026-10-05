import 'dart:async';

import 'deploy_checklist.dart';
import 'deploy_console.dart';
import 'deploy_job.dart';

/// Finish or fail the active deploy, then promote the next waiter.
class ActiveDeployCompletion({
  required final DeployConsole _console,
  required final Future<void> Function() _stopLogFollow,
  required final Future<void> Function() _clearSession,
  required final Future<void> Function() _onPromoteNext,
}) {
  bool _finishInFlight = false;

  Future<void> finish({
    required int exitCode,
    required String projectPath,
    bool cancelled = false,
  }) async {
    if (_finishInFlight) return;
    final currentJob = _console.job;
    if (currentJob == null || currentJob.status.isTerminal) return;
    _finishInFlight = true;
    try {
      await _finishJob(
        currentJob: currentJob,
        exitCode: exitCode,
        projectPath: projectPath,
        cancelled: cancelled,
      );
    } finally {
      _finishInFlight = false;
    }
  }

  Future<void> _finishJob({
    required DeployJob currentJob,
    required int exitCode,
    required String projectPath,
    required bool cancelled,
  }) async {
    await _stopLogFollow();
    _console.flush();
    final succeeded = !cancelled && exitCode == 0;
    _console.append(
      cancelled
          ? '\n✗ Deploy cancelled\n'
          : succeeded
          ? '\n✓ Deploy finished successfully\n'
          : '\n✗ Deploy failed (exit $exitCode)\n',
    );
    final finishedJob = _console.job ?? currentJob;
    final finishedAt = DateTime.now();
    await _recordTerminalAndPromote(
      finishedJob: finishedJob.copyWith(
        status: succeeded ? DeployJobStatus.succeeded : DeployJobStatus.failed,
        finishedAt: finishedAt,
        exitCode: exitCode,
        checklist: DeployChecklist.advanceToPhase(
          finishedJob.checklist,
          succeeded ? 'done' : 'failed',
          at: finishedAt,
        ),
      ),
      projectPath: projectPath,
    );
  }

  Future<void> failInterrupted({
    required DeployJob job,
    required String projectPath,
    required String message,
  }) async {
    if (_finishInFlight) return;
    if (job.status.isTerminal) return;
    _finishInFlight = true;
    try {
      await _failInterrupted(
        job: job,
        projectPath: projectPath,
        message: message,
      );
    } finally {
      _finishInFlight = false;
    }
  }

  Future<void> _failInterrupted({
    required DeployJob job,
    required String projectPath,
    required String message,
  }) async {
    final finishedAt = DateTime.now();
    await _recordTerminalAndPromote(
      finishedJob: job.copyWith(
        status: DeployJobStatus.failed,
        finishedAt: finishedAt,
        exitCode: -1,
        log: '${job.log}\n$message',
        checklist: DeployChecklist.advanceToPhase(
          job.checklist,
          'failed',
          at: finishedAt,
        ),
      ),
      projectPath: projectPath,
    );
  }

  Future<void> _recordTerminalAndPromote({
    required DeployJob finishedJob,
    required String projectPath,
  }) async {
    _console.updateStatusWithoutNewLog(finishedJob);
    await _clearSession();
    unawaited(_console.finalize(finishedJob));
    await _console.recordFinished(finishedJob, projectPath: projectPath);
    await _onPromoteNext();
  }
}
