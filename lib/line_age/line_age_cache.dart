import 'dart:async';
import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'line_age_analyzer.dart';
import 'line_age_cache_persistence.dart';
import 'line_age_report.dart';
import 'project_source.dart';

class const _LineAgeCacheEntry({
  required final String fingerprint,
  required final LineAgeReport report,
});

/// Line age reports keyed by git root, persisted across app restarts.
class LineAgeCache._() extends ChangeNotifier {
  static final LineAgeCache instance = LineAgeCache._();

  final Map<String, _LineAgeCacheEntry> _entries = {};
  LineAgeCachePersistence _persistence = LineAgeCachePersistence();
  bool _persistToDisk = true;
  Future<void>? _loadFuture;

  /// Loads cached reports from disk once per process (no-op if already loaded).
  Future<void> ensureLoaded() {
    return _loadFuture ??= _loadFromDisk();
  }

  /// Test hook — clears memory state and optionally swaps the persistence root.
  void resetForTest({Directory? persistenceDirectory}) {
    _entries.clear();
    _loadFuture = null;
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
        _entries.putIfAbsent(
          record.key,
          () => _LineAgeCacheEntry(
            fingerprint: record.value.fingerprint,
            report: record.value.report,
          ),
        );
      }
      notifyListeners();
    } catch (_) {
      // Disk cache is best-effort — in-memory entries still work this session.
    }
  }

  /// Absolute git-root path used as the cache key for [repoPath].
  static String? gitRootFor(String repoPath) =>
      LineAgeAnalyzer.findGitRoot(repoPath);

  /// Fingerprint of project source: count + path/size/mtime/ctime.
  static String computeFingerprint(String gitRoot) =>
      ProjectSource.at(gitRoot).fingerprint;

  /// Last stored report for [gitRoot], even if the dart tree has changed.
  LineAgeReport? lastStoredReport(String gitRoot) =>
      _entries[path.normalize(gitRoot)]?.report;

  bool isFingerprintCurrent(String gitRoot) {
    final normalizedRoot = path.normalize(gitRoot);
    final entry = _entries[normalizedRoot];
    if (entry == null) return false;
    return entry.fingerprint == computeFingerprint(normalizedRoot);
  }

  /// Compact SLOC for the workbench button from the last stored report.
  /// Freshness is checked when opening Line age, not on every list paint.
  String slocSubtitleForRepoPath(String repoPath) {
    final gitRoot = gitRootFor(repoPath);
    if (gitRoot == null) return '…';
    final entry = _entries[path.normalize(gitRoot)];
    if (entry == null) return '…';
    return entry.report.totalLines.asCompactCount;
  }

  void put({
    required String gitRoot,
    required String fingerprint,
    required LineAgeReport report,
  }) {
    final normalizedRoot = path.normalize(gitRoot);
    _entries[normalizedRoot] = _LineAgeCacheEntry(
      fingerprint: fingerprint,
      report: report,
    );
    notifyListeners();
    if (_persistToDisk) {
      unawaited(
        _persistence.write(
          gitRoot: normalizedRoot,
          fingerprint: fingerprint,
          report: report,
        ),
      );
    }
  }

  /// Returns a fresh cached report, or runs blame and stores the result.
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
    final fingerprint = computeFingerprint(normalizedRoot);
    final existing = _entries[normalizedRoot];
    if (existing != null && existing.fingerprint == fingerprint) {
      return existing.report;
    }

    final report = await LineAgeAnalyzer(repoPath: repoPath)
        .analyze(onProgress: onProgress);
    put(gitRoot: normalizedRoot, fingerprint: fingerprint, report: report);
    return report;
  }
}
