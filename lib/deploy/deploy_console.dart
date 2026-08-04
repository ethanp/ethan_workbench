import 'dart:async';
import 'dart:io';

import '../sync/deploy_ledger.dart';
import 'deploy_checklist.dart';
import 'deploy_cursor_mirror.dart';
import 'deploy_job.dart';

/// Live deploy console: line buffer, checklist phases, Cursor mirror, ledger.
class DeployConsole {
  DeployConsole({required this.onJobUpdated});

  final void Function(DeployJob job) onJobUpdated;

  DeployJob? _job;
  String? _projectPath;
  String _lineBuffer = '';
  DeployLedger? _ledger;
  Timer? _ledgerFlushTimer;
  int _logCharsAtLastFlush = 0;
  final _logListeners = <String, Set<StreamController<String>>>{};

  static const _ledgerFlushInterval = Duration(seconds: 2);
  static const _ledgerFlushMinChars = 4096;

  DeployJob? get job => _job;
  String? get projectPath => _projectPath;

  void attachLedger(DeployLedger? ledger) {
    _ledger = ledger;
  }

  /// Bind a fresh job for a new run and kick off Cursor/ledger side effects.
  void begin(DeployJob job, {required String projectPath}) {
    _job = job;
    _projectPath = projectPath;
    _lineBuffer = '';
    _logCharsAtLastFlush = 0;
    _cancelLedgerFlush();
    onJobUpdated(job);
    unawaited(DeployCursorMirror.beginJob(job, projectPath: projectPath));
    unawaited(_ledger?.recordRunStarted(job));
  }

  /// Rewrite mirror from an in-memory job (e.g. after reclaim).
  void seed(DeployJob job, {required String projectPath}) {
    _job = job;
    _projectPath = projectPath;
    _lineBuffer = '';
    _logCharsAtLastFlush = job.log.length;
    _cancelLedgerFlush();
    onJobUpdated(job);
    unawaited(DeployCursorMirror.seedJob(job, projectPath: projectPath));
    unawaited(flushLedgerProgress());
  }

  /// Status / checklist update without new log text.
  void applyJob(DeployJob job) {
    _job = job;
    onJobUpdated(job);
    DeployCursorMirror.scheduleStatus(job, projectPath: _projectPath);
    if (!job.status.isTerminal) {
      scheduleLedgerFlush();
    }
  }

  void append(String chunk) {
    _lineBuffer += chunk;
    final splitLines = _lineBuffer.split('\n');
    _lineBuffer = splitLines.removeLast();
    for (final line in splitLines) {
      _consumeLine(line);
    }
  }

  void flush() {
    if (_lineBuffer.isEmpty) return;
    _consumeLine(_lineBuffer);
    _lineBuffer = '';
  }

  Future<void> finalize(DeployJob job) async {
    _cancelLedgerFlush();
    _job = job;
    onJobUpdated(job);
    await DeployCursorMirror.finalize(job, projectPath: _projectPath);
  }

  Future<void> recordFinished(
    DeployJob job, {
    required String projectPath,
  }) async {
    _cancelLedgerFlush();
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
    _logCharsAtLastFlush = job.log.length;
  }

  Stream<String> watch(String jobId) {
    final controller = StreamController<String>();
    final listeners = _logListeners.putIfAbsent(jobId, () => {});
    listeners.add(controller);

    final currentJob = _job;
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

  void scheduleLedgerFlush() {
    if (_ledger == null || _job == null) return;
    final grew = _job!.log.length - _logCharsAtLastFlush;
    if (grew >= _ledgerFlushMinChars) {
      _cancelLedgerFlush();
      unawaited(flushLedgerProgress());
      return;
    }
    _ledgerFlushTimer ??= Timer(_ledgerFlushInterval, () {
      _ledgerFlushTimer = null;
      unawaited(flushLedgerProgress());
    });
  }

  Future<void> flushLedgerProgress() async {
    final ledger = _ledger;
    final job = _job;
    if (ledger == null || job == null) return;
    _logCharsAtLastFlush = job.log.length;
    await ledger.flushRunProgress(job);
  }

  Future<void> dispose() async {
    _cancelLedgerFlush();
    for (final listeners in _logListeners.values) {
      for (final controller in listeners) {
        await controller.close();
      }
    }
    _logListeners.clear();
  }

  void _consumeLine(String line) {
    if (line.startsWith(DeployChecklist.phasePrefix)) {
      final phaseId = line.substring(DeployChecklist.phasePrefix.length).trim();
      if (phaseId.isEmpty) return;
      final currentJob = _job;
      if (currentJob == null) return;
      applyJob(
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
    final currentJob = _job;
    if (currentJob == null) return;
    final updatedJob = currentJob.copyWith(log: currentJob.log + chunk);
    _job = updatedJob;
    onJobUpdated(updatedJob);
    unawaited(DeployCursorMirror.appendLog(chunk));
    DeployCursorMirror.scheduleStatus(
      updatedJob,
      projectPath: _projectPath,
    );
    scheduleLedgerFlush();
    final listeners = _logListeners[currentJob.jobId];
    if (listeners == null) return;
    for (final controller in listeners) {
      if (!controller.isClosed) controller.add(chunk);
    }
  }

  void _cancelLedgerFlush() {
    _ledgerFlushTimer?.cancel();
    _ledgerFlushTimer = null;
  }
}
