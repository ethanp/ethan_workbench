import 'line_age_cache.dart';
import 'line_age_directory_groups.dart';
import 'line_age_report.dart';

/// One Line age chart subject — a single repo or the Flutter fleet.
abstract class LineAgeAnalysis() {
  String get title;

  LineAgeDirectoryLegend legendFor(LineAgeReport report);

  /// Inserted between last-touched and file count (`11 repos`), or omitted.
  String? extraCaption(LineAgeReport report);

  Future<LineAgeReport> analyzeOrCached({
    void Function(LineAgeProgress progress)? onProgress,
    void Function(LineAgeReport partial)? onPartialReport,
  });

  void cancel();
}

/// Last-touched months for one git checkout.
class const RepoLineAge({
  required final String repoPath,
  required final String repoName,
}) implements LineAgeAnalysis {
  @override
  String get title => repoName;

  @override
  LineAgeDirectoryLegend legendFor(LineAgeReport report) =>
      LineAgeDirectoryGroups.legendFor(report);

  @override
  String? extraCaption(LineAgeReport report) => null;

  @override
  Future<LineAgeReport> analyzeOrCached({
    void Function(LineAgeProgress progress)? onProgress,
    void Function(LineAgeReport partial)? onPartialReport,
  }) async {
    await LineAgeCache.instance.ensureLoaded();
    final gitRoot = LineAgeCache.gitRootFor(repoPath);
    if (gitRoot != null) {
      final stored = LineAgeCache.instance.lastStoredReport(gitRoot);
      if (stored != null) onPartialReport?.call(stored);
    }
    return LineAgeCache.instance.analyzeOrCached(
      repoPath,
      onProgress: onProgress,
    );
  }

  @override
  void cancel() => LineAgeCache.instance.cancelAnalyze(repoPath);
}
