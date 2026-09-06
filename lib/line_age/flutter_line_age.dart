import 'dart:collection';
import 'dart:math' as math;

import 'package:ethan_utils/ethan_utils.dart';
import 'package:path/path.dart' as path;

import 'flutter_git_repos.dart';
import 'line_age_analysis.dart';
import 'line_age_cache.dart';
import 'line_age_directory_groups.dart';
import 'line_age_repo_groups.dart';
import 'line_age_report.dart';

const _logger = ELogger('FlutterLineAge');

/// Last-touched months across every immediate git checkout under Flutter roots.
class FlutterLineAge({required final List<String> flutterRoots})
    implements LineAgeAnalysis {
  static const _maxConcurrentBlames = 2;

  final FlutterGitRepos _flutterGitRepos = FlutterGitRepos(
    flutterRoots: flutterRoots,
  );
  bool _cancelled = false;

  List<String> get gitRoots => _flutterGitRepos.gitRoots;

  @override
  String get title => LineAgeReport.flutterFleetName;

  @override
  LineAgeDirectoryLegend legendFor(LineAgeReport report) =>
      LineAgeRepoGroups.legendFor(report);

  @override
  String? extraCaption(LineAgeReport report) => '${gitRoots.length} repos';

  /// Compact SLOC from whatever fleet reports are already cached.
  String cachedSlocSubtitle() {
    var totalLines = 0;
    var hasCachedReport = false;
    for (final gitRoot in gitRoots) {
      final report = LineAgeCache.instance.lastStoredReport(gitRoot);
      if (report == null) continue;
      hasCachedReport = true;
      totalLines += report.totalLines;
    }
    if (!hasCachedReport) return 'All repos';
    return totalLines.asCompactCount;
  }

  @override
  void cancel() {
    _cancelled = true;
    for (final gitRoot in gitRoots) {
      LineAgeCache.instance.cancelAnalyze(gitRoot);
    }
  }

  @override
  Future<LineAgeReport> analyzeOrCached({
    void Function(LineAgeProgress progress)? onProgress,
    void Function(LineAgeReport partial)? onPartialReport,
  }) async {
    await LineAgeCache.instance.ensureLoaded();
    final roots = gitRoots;
    if (roots.isEmpty) {
      return LineAgeReport.acrossRepos(const []);
    }

    final reportsByRoot = <String, LineAgeReport>{};
    for (final gitRoot in roots) {
      final stored = LineAgeCache.instance.lastStoredReport(gitRoot);
      if (stored != null) reportsByRoot[gitRoot] = stored;
    }
    _emitPartial(reportsByRoot, onPartialReport);

    final blameProgress = _FleetBlameProgress.fromCachedReports(reportsByRoot);
    _emitProgress(
      onProgress,
      completedFiles: blameProgress.completedFiles,
      totalFiles: blameProgress.totalFiles,
      currentRelativePath: '',
    );

    await _analyzeStaleRoots(
      roots: roots,
      reportsByRoot: reportsByRoot,
      onPartialReport: onPartialReport,
      onProgress: onProgress,
      blameProgress: blameProgress,
    );

    if (_cancelled) {
      throw StateError('Line age analysis cancelled.');
    }
    return LineAgeReport.acrossRepos(reportsByRoot.values.toList());
  }

  Future<void> _analyzeStaleRoots({
    required List<String> roots,
    required Map<String, LineAgeReport> reportsByRoot,
    required void Function(LineAgeReport partial)? onPartialReport,
    required void Function(LineAgeProgress progress)? onProgress,
    required _FleetBlameProgress blameProgress,
  }) async {
    final pending = Queue<String>.of(roots);
    Future<void> worker() async {
      while (pending.isNotEmpty && !_cancelled) {
        await _analyzeOneGitRoot(
          gitRoot: pending.removeFirst(),
          reportsByRoot: reportsByRoot,
          onPartialReport: onPartialReport,
          onProgress: onProgress,
          blameProgress: blameProgress,
        );
      }
    }

    final workerCount = math.min(_maxConcurrentBlames, roots.length);
    await Future.wait([
      for (var index = 0; index < workerCount; index++) worker(),
    ]);
  }

  Future<void> _analyzeOneGitRoot({
    required String gitRoot,
    required Map<String, LineAgeReport> reportsByRoot,
    required void Function(LineAgeReport partial)? onPartialReport,
    required void Function(LineAgeProgress progress)? onProgress,
    required _FleetBlameProgress blameProgress,
  }) async {
    if (_cancelled) return;
    var lastCompletedInThisRepo = 0;
    try {
      final report = await LineAgeCache.instance.analyzeOrCached(
        gitRoot,
        onProgress: (progress) {
          if (_cancelled) return;
          blameProgress.countRootFiles(gitRoot, progress.totalFiles);
          blameProgress.addCompleted(
            progress.completedFiles - lastCompletedInThisRepo,
          );
          lastCompletedInThisRepo = progress.completedFiles;
          _emitProgress(
            onProgress,
            completedFiles: blameProgress.completedFiles,
            totalFiles: blameProgress.totalFiles,
            currentRelativePath:
                '${path.basename(gitRoot)}/${progress.currentRelativePath}',
          );
        },
      );
      if (_cancelled) return;
      if (lastCompletedInThisRepo == 0) {
        blameProgress.addCompleted(report.fileCount);
      }
      reportsByRoot[gitRoot] = report;
      _emitPartial(reportsByRoot, onPartialReport);
    } catch (error, stackTrace) {
      _logger.warn('Fleet line age failed for $gitRoot', error, stackTrace);
    }
  }

  void _emitPartial(
    Map<String, LineAgeReport> reportsByRoot,
    void Function(LineAgeReport partial)? onPartialReport,
  ) {
    if (onPartialReport == null || reportsByRoot.isEmpty) return;
    onPartialReport(LineAgeReport.acrossRepos(reportsByRoot.values.toList()));
  }

  void _emitProgress(
    void Function(LineAgeProgress progress)? onProgress, {
    required int completedFiles,
    required int totalFiles,
    required String currentRelativePath,
  }) {
    onProgress?.call(
      LineAgeProgress(
        completedFiles: completedFiles,
        totalFiles: totalFiles,
        currentRelativePath: currentRelativePath,
      ),
    );
  }
}

class _FleetBlameProgress() {
  var completedFiles = 0;
  var totalFiles = 0;
  final Set<String> _rootsCountedInTotal = {};

  factory fromCachedReports(Map<String, LineAgeReport> reportsByRoot) {
    final progress = _FleetBlameProgress();
    for (final entry in reportsByRoot.entries) {
      progress.countRootFiles(entry.key, entry.value.fileCount);
    }
    return progress;
  }

  void addCompleted(int delta) => completedFiles += delta;

  void countRootFiles(String gitRoot, int fileCount) {
    if (_rootsCountedInTotal.add(gitRoot)) totalFiles += fileCount;
  }
}
