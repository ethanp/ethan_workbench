import 'dart:convert';
import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:path/path.dart' as path;

import 'line_age_analysis_cancelled.dart';
import 'line_age_report.dart';
import 'project_source.dart';

/// Surviving project-source lines bucketed by last-touched month.
class LastTouchedMonths(final ProjectSource projectSource) {
  /// Shared by every repo, so the fleet and the homescreen together never
  /// run more blames than there are cores.
  static final ConcurrencyLimit _blameLimit = ConcurrencyLimit(
    Platform.numberOfProcessors,
  );

  bool _cancelled = false;

  void cancel() => _cancelled = true;

  /// Blames every counted file except those in [reusableLinesByFile], whose
  /// earlier month counts are kept as they are.
  Future<LineAgeReport> measure({
    void Function(LineAgeProgress progress)? onProgress,
    Map<String, Map<String, int>> reusableLinesByFile = const {},
  }) async {
    final countedPaths = projectSource.countedRelativePaths;
    if (countedPaths.isEmpty) {
      throw StateError('No project source files found.');
    }

    final linesByFile = <String, Map<String, int>>{
      for (final relativePath in countedPaths)
        relativePath: ?reusableLinesByFile[relativePath],
    };
    final pathsToBlame = [
      for (final relativePath in countedPaths)
        if (!linesByFile.containsKey(relativePath)) relativePath,
    ];
    var completedFiles = linesByFile.length;
    await Future.wait([
      for (final relativePath in pathsToBlame)
        _blameLimit.run(() async {
          if (_cancelled) throw const LineAgeAnalysisCancelled();
          onProgress?.call(
            LineAgeProgress(
              completedFiles: completedFiles,
              totalFiles: countedPaths.length,
              currentRelativePath: relativePath,
            ),
          );
          linesByFile[relativePath] = await _lastTouchedCounts(relativePath);
          completedFiles++;
        }),
    ], eagerError: true);
    if (_cancelled) throw const LineAgeAnalysisCancelled();

    onProgress?.call(
      LineAgeProgress(
        completedFiles: countedPaths.length,
        totalFiles: countedPaths.length,
        currentRelativePath: '',
      ),
    );
    return _report(linesByFile: linesByFile, fileCount: countedPaths.length);
  }

  LineAgeReport _report({
    required Map<String, Map<String, int>> linesByFile,
    required int fileCount,
  }) {
    final linesByMonthAndFile = <String, Map<String, int>>{};
    final totalByFile = <String, int>{};
    for (final fileEntry in linesByFile.entries) {
      for (final monthEntry in fileEntry.value.entries) {
        linesByMonthAndFile.putIfAbsent(
          monthEntry.key,
          () => {},
        )[fileEntry.key] = monthEntry.value;
        totalByFile.update(
          fileEntry.key,
          (count) => count + monthEntry.value,
          ifAbsent: () => monthEntry.value,
        );
      }
    }
    final sortedMonths = linesByMonthAndFile.keys.toList()..sort();

    return LineAgeReport(
      repoName: path.basename(projectSource.gitRoot),
      months: [
        for (final month in sortedMonths)
          _month(month, linesByMonthAndFile[month]!),
      ],
      totalLinesByFile: {
        for (final entry in _largestFirst(totalByFile)) entry.key: entry.value,
      },
      totalLines: totalByFile.values.fold(0, (sum, count) => sum + count),
      fileCount: fileCount,
    );
  }

  /// Ties break by path so concurrent blames still give a stable order.
  List<MapEntry<String, int>> _largestFirst(Map<String, int> countsByFile) =>
      countsByFile.entries.toList()..sort((left, right) {
        final byCount = right.value.compareTo(left.value);
        if (byCount != 0) return byCount;
        return left.key.compareTo(right.key);
      });

  LineAgeMonth _month(String month, Map<String, int> linesByFile) {
    return LineAgeMonth(
      month: month,
      totalLines: linesByFile.values.fold(0, (sum, count) => sum + count),
      segments: [
        for (final entry in _largestFirst(linesByFile))
          LineAgeSegment(file: entry.key, lineCount: entry.value),
      ],
    );
  }

  Future<Map<String, int>> _lastTouchedCounts(String relativePath) async {
    final process = await Process.run(
      'git',
      ['blame', '--incremental', '--', relativePath],
      workingDirectory: projectSource.gitRoot,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (process.exitCode != 0) {
      return _workingTreeLinesLastTouchedThisMonth(relativePath);
    }
    return _linesByMonthFromIncrementalBlame(process.stdout as String);
  }

  /// `--incremental` prints each commit's headers only the first time that
  /// commit appears; every line group ends with a `filename` line.
  Map<String, int> _linesByMonthFromIncrementalBlame(String blameOutput) {
    final committedAtByCommit = <String, int>{};
    final linesByMonth = <String, int>{};
    String? groupCommit;
    var groupLineCount = 0;
    for (final line in const LineSplitter().convert(blameOutput)) {
      if (groupCommit == null) {
        final headerParts = line.split(' ');
        if (headerParts.length != 4) continue;
        groupCommit = headerParts[0];
        groupLineCount = int.tryParse(headerParts[3]) ?? 0;
        continue;
      }
      if (line.startsWith('committer-time ')) {
        final seconds = int.tryParse(line.substring('committer-time '.length));
        if (seconds != null) committedAtByCommit[groupCommit] = seconds;
        continue;
      }
      if (!line.startsWith('filename ')) continue;
      final seconds = committedAtByCommit[groupCommit];
      groupCommit = null;
      if (seconds == null) continue;
      final month = DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000,
        isUtc: true,
      ).yearMonthKey;
      linesByMonth.update(
        month,
        (count) => count + groupLineCount,
        ifAbsent: () => groupLineCount,
      );
    }
    return linesByMonth;
  }

  Map<String, int> _workingTreeLinesLastTouchedThisMonth(String relativePath) {
    final file = File(path.join(projectSource.gitRoot, relativePath));
    try {
      final lineCount = file.readAsLinesSync().length;
      if (lineCount == 0) return {};
      return {DateTime.now().toUtc().yearMonthKey: lineCount};
    } on FileSystemException {
      return {};
    }
  }
}
