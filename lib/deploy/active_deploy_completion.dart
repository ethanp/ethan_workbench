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
  Future<void> finish({
    required int exitCode,
    required String projectPath,
  }) async {
    await _stopLogFollow();
    _console.flush();
    final succeeded = exitCode == 0;
    _console.append(
      succeeded
          ? '\n✓ Deploy finished successfully\n'
          : '\n✗ Deploy failed (exit $exitCode)\n',
    );
    final currentJob = _console.job!;
    final finishedAt = DateTime.now();
    await _recordTerminalAndPromote(
      finishedJob: currentJob.copyWith(
        status: succeeded ? DeployJobStatus.succeeded : DeployJobStatus.failed,
        finishedAt: finishedAt,
        exitCode: exitCode,
        checklist: DeployChecklist.advanceToPhase(
          currentJob.checklist,
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
