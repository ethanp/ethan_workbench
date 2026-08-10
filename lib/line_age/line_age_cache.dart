import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'line_age_analyzer.dart';

class _LineAgeCacheEntry {
  const _LineAgeCacheEntry({
    required this.fingerprint,
    required this.report,
  });

  final String fingerprint;
  final LineAgeReport report;
}

/// In-memory Line age reports, invalidated when the Dart tree fingerprint changes.
class LineAgeCache extends ChangeNotifier {
  LineAgeCache._();

  static final LineAgeCache instance = LineAgeCache._();

  final Map<String, _LineAgeCacheEntry> _entries = {};

  /// Absolute git-root path used as the cache key for [repoPath].
  static String? gitRootFor(String repoPath) =>
      LineAgeAnalyzer.findGitRoot(repoPath);

  /// Fingerprint of non-generated Dart files under [gitRoot].
  static String computeFingerprint(String gitRoot) {
    final dartFiles = LineAgeAnalyzer.listDartFiles(gitRoot);
    final parts = <String>[
      for (final file in dartFiles)
        '${path.relative(file.path, from: gitRoot)}:'
            '${file.lengthSync()}:'
            '${file.lastModifiedSync().millisecondsSinceEpoch}',
    ];
    return Object.hashAll(parts).toString();
  }

  LineAgeReport? cachedReport(String gitRoot) {
    final entry = _entries[gitRoot];
    if (entry == null) return null;
    final fingerprint = computeFingerprint(gitRoot);
    if (entry.fingerprint != fingerprint) return null;
    return entry.report;
  }

  int? cachedTotalLines(String gitRoot) => cachedReport(gitRoot)?.totalLines;

  /// Compact SLOC for the workbench button from the last stored report.
  /// Freshness is checked when opening Line age, not on every list paint.
  String slocSubtitleForRepoPath(String repoPath) {
    final gitRoot = gitRootFor(repoPath);
    if (gitRoot == null) return '…';
    final entry = _entries[gitRoot];
    if (entry == null) return '…';
    return entry.report.totalLines.asCompactCount;
  }

  void put({
    required String gitRoot,
    required String fingerprint,
    required LineAgeReport report,
  }) {
    _entries[gitRoot] = _LineAgeCacheEntry(
      fingerprint: fingerprint,
      report: report,
    );
    notifyListeners();
  }

  /// Returns a fresh cached report, or runs blame and stores the result.
  Future<LineAgeReport> analyzeOrCached(
    String repoPath, {
    void Function(LineAgeProgress progress)? onProgress,
  }) async {
    final gitRoot = gitRootFor(repoPath);
    if (gitRoot == null) {
      throw StateError('Not inside a git repository: $repoPath');
    }
    final fingerprint = computeFingerprint(gitRoot);
    final existing = _entries[gitRoot];
    if (existing != null && existing.fingerprint == fingerprint) {
      return existing.report;
    }

    final report = await LineAgeAnalyzer(repoPath: repoPath).analyze(
      onProgress: onProgress,
    );
    put(gitRoot: gitRoot, fingerprint: fingerprint, report: report);
    return report;
  }
}
