import 'dart:io';

import 'package:path/path.dart' as path;

import 'last_touched_months.dart';
import 'line_age_report.dart';
import 'project_size_through_months.dart';
import 'project_source.dart';

/// Measures last-touched months and project size for a git checkout.
///
/// [repoPath] may be any directory inside a git checkout. Analysis covers the
/// whole git root once found.
class LineAgeAnalyzer({
  required final String repoPath,
  final ProjectSource? projectSource,
}) {
  bool _cancelled = false;
  LastTouchedMonths? _lastTouchedMonths;
  ProjectSizeThroughMonths? _projectSizeThroughMonths;

  void cancel() {
    _cancelled = true;
    _lastTouchedMonths?.cancel();
    _projectSizeThroughMonths?.cancel();
  }

  /// Walks from [startPath] upward until a `.git` directory or file is found.
  static String? findGitRoot(String startPath) {
    var current = path.normalize(startPath);
    while (true) {
      final gitMarker = path.join(current, '.git');
      if (Directory(gitMarker).existsSync() || File(gitMarker).existsSync()) {
        return current;
      }
      final parent = path.dirname(current);
      if (parent == current) return null;
      current = parent;
    }
  }

  Future<LineAgeReport> analyze({
    void Function(LineAgeProgress progress)? onProgress,
  }) async {
    if (!Directory(repoPath).existsSync()) {
      throw StateError('Not a directory: $repoPath');
    }
    final gitRoot = findGitRoot(repoPath);
    if (gitRoot == null) {
      throw StateError('Not inside a git repository: $repoPath');
    }
    if (_cancelled) {
      throw StateError('Line age analysis cancelled.');
    }

    final analyzedSource = projectSource ?? ProjectSource.at(gitRoot);
    final lastTouchedMonths = LastTouchedMonths(analyzedSource);
    final projectSizeThroughMonths = ProjectSizeThroughMonths(analyzedSource);
    _lastTouchedMonths = lastTouchedMonths;
    _projectSizeThroughMonths = projectSizeThroughMonths;

    final lastTouched = await lastTouchedMonths.measure(onProgress: onProgress);
    if (_cancelled) {
      throw StateError('Line age analysis cancelled.');
    }
    final yearMonths = [
      for (final month in lastTouched.timelineMonths) month.month,
    ];
    if (yearMonths.isEmpty) return lastTouched;
    final projectSizeByMonth = await projectSizeThroughMonths.along(yearMonths);
    return lastTouched.withProjectSize(projectSizeByMonth);
  }
}
