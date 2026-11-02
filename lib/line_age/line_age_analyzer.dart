import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:path/path.dart' as path;

import 'last_touched_months.dart';
import 'line_age_analysis_cancelled.dart';
import 'line_age_report.dart';
import 'project_size_through_months.dart';
import 'project_source.dart';
import 'project_source_git_state.dart';

/// A line age report and the git state it was measured against.
class const MeasuredLineAge({
  required final ProjectSourceGitState gitState,
  required final LineAgeReport report,
}) {
  /// Month-end sizes for months that closed before the measured HEAD commit.
  /// Commits added on top of that HEAD cannot change them.
  ProjectSizeByMonth get settledProjectSize {
    final headCommittedAt = gitState.headCommittedAt;
    if (headCommittedAt == null) return const ProjectSizeByMonth();
    return report.projectSizeByMonth.monthsBefore(
      headCommittedAt.toLocal().yearMonthKey,
    );
  }
}

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

  /// With [previous], files whose blame cannot have changed between
  /// [previous] and [currentGitState] keep their earlier counts, and so do
  /// [MeasuredLineAge.settledProjectSize] months.
  Future<LineAgeReport> analyze({
    void Function(LineAgeProgress progress)? onProgress,
    MeasuredLineAge? previous,
    ProjectSourceGitState? currentGitState,
  }) async {
    if (!Directory(repoPath).existsSync()) {
      throw StateError('Not a directory: $repoPath');
    }
    final gitRoot = findGitRoot(repoPath);
    if (gitRoot == null) {
      throw StateError('Not inside a git repository: $repoPath');
    }
    if (_cancelled) {
      throw const LineAgeAnalysisCancelled();
    }

    final analyzedSource = projectSource ?? ProjectSource.at(gitRoot);
    final lastTouchedMonths = LastTouchedMonths(analyzedSource);
    final projectSizeThroughMonths = ProjectSizeThroughMonths(analyzedSource);
    _lastTouchedMonths = lastTouchedMonths;
    _projectSizeThroughMonths = projectSizeThroughMonths;

    final pathsToReblame = previous == null || currentGitState == null
        ? null
        : await currentGitState.pathsToReblameSince(
            previous.gitState,
            gitRoot: gitRoot,
          );
    final lastTouched = await lastTouchedMonths.measure(
      onProgress: onProgress,
      reusableLinesByFile: pathsToReblame == null
          ? const {}
          : (previous!.report.lastTouchedLinesByFile..removeWhere(
              (relativePath, _) => pathsToReblame.contains(relativePath),
            )),
    );
    if (_cancelled) {
      throw const LineAgeAnalysisCancelled();
    }
    final yearMonths = lastTouched.timelineMonths.mapL((month) => month.month);
    if (yearMonths.isEmpty) return lastTouched;
    final projectSizeByMonth = await projectSizeThroughMonths.along(
      yearMonths,
      settledSizes: pathsToReblame == null
          ? const ProjectSizeByMonth()
          : previous!.settledProjectSize,
    );
    return lastTouched.withProjectSize(projectSizeByMonth);
  }
}
