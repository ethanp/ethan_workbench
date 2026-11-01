import 'dart:async';
import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'line_age_analysis_cancelled.dart';
import 'line_age_analyzer.dart';
import 'line_age_cache_persistence.dart';
import 'line_age_report.dart';
import 'project_source.dart';
import 'project_source_git_state.dart';

/// One shared analysis for a git root. Cancellation is global to that root:
/// [cancel] stops the underlying work and every waiter receives the error.
class _LineAgeInFlight({
  required final Future<LineAgeReport> report,
  required final void Function() cancel,
  required final List<void Function(LineAgeProgress)> progressListeners,
});

/// Line age reports keyed by git root, persisted across app restarts.
class LineAgeCache._() extends ChangeNotifier {
  static final LineAgeCache instance = LineAgeCache._();

  final Map<String, MeasuredLineAge> _entries = {};
  final Map<String, _LineAgeInFlight> _inFlight = {};
  LineAgeCachePersistence _persistence = LineAgeCachePersistence();
  bool _persistToDisk = true;
  Future<void>? _loadFuture;
  Future<LineAgeReport> Function(
    String repoPath,
    void Function(LineAgeProgress)? onProgress,
  )?
  _analyzeOverride;

  /// Loads cached reports from disk once per process (no-op if already loaded).
  Future<void> ensureLoaded() {
    return _loadFuture ??= _loadFromDisk();
  }

  /// Test hook — clears memory state and optionally swaps the persistence root.
  void resetForTest({
    Directory? persistenceDirectory,
    Future<LineAgeReport> Function(
      String repoPath,
      void Function(LineAgeProgress)? onProgress,
    )?
    analyzeOverride,
  }) {
    _entries.clear();
    _inFlight.clear();
    _loadFuture = null;
    _analyzeOverride = analyzeOverride;
    if (persistenceDirectory == null) {
      _persistToDisk = false;
      return;
    }
    _persistToDisk = true;
    _persistence = LineAgeCachePersistence(
      directoryOverride: persistenceDirectory,
    );
  }

  Future<void> _loadFromDisk() async {
    if (!_persistToDisk) return;
    try {
      final records = await _persistence.readAll();
      for (final record in records.entries) {
        _entries.putIfAbsent(record.key, () => record.value.measured);
      }
      notifyListeners();
    } catch (_) {
      // Disk cache is best-effort — in-memory entries still work this session.
    }
  }

  /// Absolute git-root path used as the cache key for [repoPath].
  static String? gitRootFor(String repoPath) =>
      LineAgeAnalyzer.findGitRoot(repoPath);

  /// Last stored report for [gitRoot], even if project source has changed.
  LineAgeReport? lastStoredReport(String gitRoot) =>
      _entries[path.normalize(gitRoot)]?.report;

  /// Compact SLOC for the workbench button from the last stored report.
  /// Freshness is checked when opening Line age, not on every list paint.
  String slocSubtitleForRepoPath(String repoPath) {
    final gitRoot = gitRootFor(repoPath);
    if (gitRoot == null) return '…';
    final entry = _entries[path.normalize(gitRoot)];
    if (entry == null) return '…';
    return entry.report.totalLines.asCompactCount;
  }

  void put({required String gitRoot, required MeasuredLineAge measured}) {
    final normalizedRoot = path.normalize(gitRoot);
    _entries[normalizedRoot] = measured;
    notifyListeners();
    if (_persistToDisk) {
      unawaited(
        _persistence.write(gitRoot: normalizedRoot, measured: measured),
      );
    }
  }

  /// Returns the stored report when git state is unchanged; otherwise
  /// reblames only the files that changed since it and stores the result.
  Future<LineAgeReport> analyzeOrCached(
    String repoPath, {
    void Function(LineAgeProgress progress)? onProgress,
  }) async {
    await ensureLoaded();
    final gitRoot = gitRootFor(repoPath);
    if (gitRoot == null) {
      throw StateError('Not inside a git repository: $repoPath');
    }
    final normalizedRoot = path.normalize(gitRoot);
    var flight = _inFlight[normalizedRoot];
    if (flight == null) {
      final projectSource = ProjectSource.at(normalizedRoot);
      final gitState = await ProjectSourceGitState.read(projectSource);
      final previous = _entries[normalizedRoot];
      if (previous != null && previous.gitState == gitState) {
        return previous.report;
      }
      flight = _claimInFlight(
        repoPath: repoPath,
        normalizedRoot: normalizedRoot,
        projectSource: projectSource,
        previous: previous,
        gitState: gitState,
      );
    }
    if (onProgress != null) flight.progressListeners.add(onProgress);
    try {
      return await flight.report;
    } finally {
      if (identical(_inFlight[normalizedRoot], flight)) {
        _inFlight.remove(normalizedRoot);
      }
    }
  }

  /// Sync claim: a caller that raced through its git read joins the same
  /// [_LineAgeInFlight]. The analysis stores its own result.
  _LineAgeInFlight _claimInFlight({
    required String repoPath,
    required String normalizedRoot,
    required ProjectSource projectSource,
    required MeasuredLineAge? previous,
    required ProjectSourceGitState gitState,
  }) {
    final existingFlight = _inFlight[normalizedRoot];
    if (existingFlight != null) return existingFlight;

    final cancelled = Completer<LineAgeReport>();
    LineAgeAnalyzer? analyzer;
    void cancel() {
      analyzer?.cancel();
      if (!cancelled.isCompleted) {
        cancelled.completeError(const LineAgeAnalysisCancelled());
      }
    }

    final progressListeners = <void Function(LineAgeProgress)>[];
    void emitProgress(LineAgeProgress progress) {
      for (final listener in List.of(progressListeners)) {
        listener(progress);
      }
    }

    final work = () async {
      final analyzeOverride = _analyzeOverride;
      final LineAgeReport report;
      if (analyzeOverride != null) {
        report = await analyzeOverride(repoPath, emitProgress);
      } else {
        final lineAgeAnalyzer = LineAgeAnalyzer(
          repoPath: repoPath,
          projectSource: projectSource,
        );
        analyzer = lineAgeAnalyzer;
        report = await lineAgeAnalyzer.analyze(
          onProgress: emitProgress,
          previous: previous,
          currentGitState: gitState,
        );
      }
      put(
        gitRoot: normalizedRoot,
        measured: MeasuredLineAge(gitState: gitState, report: report),
      );
      return report;
    }();

    final flight = _LineAgeInFlight(
      report: Future.any([work, cancelled.future]),
      cancel: cancel,
      progressListeners: progressListeners,
    );
    _inFlight[normalizedRoot] = flight;
    return flight;
  }

  /// Cancels the shared in-flight analysis for [repoPath]'s git root.
  /// Every waiter of that analysis receives the cancellation error.
  /// A later [analyzeOrCached] starts a new analysis.
  void cancelAnalyze(String repoPath) {
    final gitRoot = gitRootFor(repoPath);
    if (gitRoot == null) return;
    _inFlight[path.normalize(gitRoot)]?.cancel();
  }
}
