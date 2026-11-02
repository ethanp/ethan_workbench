import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../cursor/workbench_cursor_dirs.dart';
import 'deploy_job.dart';
import 'deploy_log_error_summary.dart';

/// Mirrors the live/last-failed deploy log for Cursor to read on disk.
///
/// Writes under:
/// - `{ethan_workbench}/.workbench/` when that package root can be resolved
/// - application support `cursor/` (always), as a fallback path
///
/// Prefer [lastFailedLogFileName] when debugging a finished failure.
abstract final class DeployCursorMirror() {
  static const logFileName = 'current_deploy.log';
  static const statusFileName = 'current_deploy_status.json';
  static const lastFailedLogFileName = 'last_failed_deploy.log';
  static const lastFailedStatusFileName = 'last_failed_deploy_status.json';

  static const _statusCoalesce = Duration(milliseconds: 150);

  static Timer? _statusDebounce;
  static DeployJob? _pendingJob;
  static String? _pendingProjectPath;
  static var _statusGeneration = 0;

  /// Test hook — drops a pending status write.
  static void resetForTest() {
    _statusDebounce?.cancel();
    _statusDebounce = null;
    _pendingJob = null;
    _pendingProjectPath = null;
    _statusGeneration = 0;
  }

  /// Clear live log and write the starting status for a new deploy.
  static Future<void> beginJob(DeployJob job, {String? projectPath}) async {
    _beginStatusGeneration();
    await WorkbenchCursorDirs.ensureResolved();
    for (final directory in WorkbenchCursorDirs.directories) {
      await WorkbenchCursorDirs.writeSafely(
        File(path.join(directory.path, logFileName)),
        '',
      );
    }
    await writeStatus(job, projectPath: projectPath);
  }

  static Future<void> appendLog(String chunk) async {
    if (chunk.isEmpty) return;
    await WorkbenchCursorDirs.ensureResolved();
    for (final directory in WorkbenchCursorDirs.directories) {
      await WorkbenchCursorDirs.writeSafely(
        File(path.join(directory.path, logFileName)),
        chunk,
        append: true,
      );
    }
  }

  /// Status sidecar (no full log — see [logFileName]).
  ///
  /// Coalesces a burst of log lines into one write. Further lines update the
  /// pending job but do not postpone that write, so a busy build still
  /// publishes status. A newer generation drops a write that resumed late.
  static void scheduleStatus(DeployJob job, {String? projectPath}) {
    _pendingJob = job;
    _pendingProjectPath = projectPath;
    if (_statusDebounce?.isActive ?? false) return;
    final generation = _statusGeneration;
    _statusDebounce = Timer(_statusCoalesce, () {
      _statusDebounce = null;
      final pending = _pendingJob;
      final pendingPath = _pendingProjectPath;
      if (pending == null || generation != _statusGeneration) return;
      unawaited(
        writeStatus(pending, projectPath: pendingPath, generation: generation),
      );
    });
  }

  static Future<void> writeStatus(
    DeployJob job, {
    String? projectPath,
    int? generation,
  }) async {
    final writeGeneration = generation ?? _statusGeneration;
    await WorkbenchCursorDirs.ensureResolved();
    if (writeGeneration != _statusGeneration) return;
    final encoded = const JsonEncoder.withIndent('  ')
        .convert(_statusPayload(job, projectPath: projectPath));
    for (final directory in WorkbenchCursorDirs.directories) {
      if (writeGeneration != _statusGeneration) return;
      await WorkbenchCursorDirs.writeSafely(
        File(path.join(directory.path, statusFileName)),
        encoded,
      );
    }
  }

  /// Rewrite the live log from an in-memory job (e.g. after reclaim).
  static Future<void> seedJob(DeployJob job, {String? projectPath}) async {
    _beginStatusGeneration();
    await WorkbenchCursorDirs.ensureResolved();
    for (final directory in WorkbenchCursorDirs.directories) {
      await WorkbenchCursorDirs.writeSafely(
        File(path.join(directory.path, logFileName)),
        job.log,
      );
    }
    await writeStatus(job, projectPath: projectPath);
  }

  /// Flush status and, on failure, write the job's full in-memory log to the
  /// stable last-failed paths Cursor should open first. The in-memory log is
  /// authoritative; the live log file is not reused for this.
  static Future<void> finalize(DeployJob job, {String? projectPath}) async {
    _beginStatusGeneration();
    await writeStatus(job, projectPath: projectPath);
    if (job.status != DeployJobStatus.failed) return;

    await WorkbenchCursorDirs.ensureResolved();
    final failedStatus = const JsonEncoder.withIndent('  ').convert(
      _statusPayload(
        job,
        projectPath: projectPath,
        logFileOverride: lastFailedLogFileName,
      ),
    );
    for (final directory in WorkbenchCursorDirs.directories) {
      await WorkbenchCursorDirs.writeSafely(
        File(path.join(directory.path, lastFailedLogFileName)),
        job.log,
      );
      await WorkbenchCursorDirs.writeSafely(
        File(path.join(directory.path, lastFailedStatusFileName)),
        failedStatus,
      );
    }
  }

  static void _beginStatusGeneration() {
    _statusGeneration += 1;
    _statusDebounce?.cancel();
    _statusDebounce = null;
    _pendingJob = null;
    _pendingProjectPath = null;
  }

  static Map<String, Object?> _statusPayload(
    DeployJob job, {
    String? projectPath,
    String? logFileOverride,
  }) {
    final failureHint = job.status == DeployJobStatus.failed
        ? DeployLogErrorSummary.failureHint(job.log)
        : null;
    final errorTail = job.status == DeployJobStatus.failed
        ? DeployLogErrorSummary.errorTail(job.log)
        : null;
    return {
      'kind': 'deploy',
      'updatedAt': DateTime.now().toIso8601String(),
      'jobId': job.jobId,
      'projectId': job.projectId,
      'projectName': job.projectName,
      'projectPath': ?projectPath,
      'platform': job.platform.name,
      'force': job.force,
      'deploy': ?job.deploy?.toJson(),
      'status': job.status.name,
      'exitCode': job.exitCode,
      'createdAt': job.createdAt.toIso8601String(),
      'finishedAt': job.finishedAt?.toIso8601String(),
      'logFile': logFileOverride ?? logFileName,
      'logLength': job.log.length,
      'lastFailedLogFile': lastFailedLogFileName,
      'lastFailedStatusFile': lastFailedStatusFileName,
      'failureHint': ?failureHint,
      if (errorTail != null && errorTail.isNotEmpty) 'errorTail': errorTail,
      'howToDebug':
          'For a failed deploy, read $lastFailedLogFileName (or errorTail / '
          'failureHint in $lastFailedStatusFileName) before the full log. '
          'While a deploy is running, use $logFileName.',
      'mirrorDirectories': WorkbenchCursorDirs.directories.mapL(
        (directory) => directory.path,
      ),
    };
  }
}
