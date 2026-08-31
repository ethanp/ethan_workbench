import 'dart:convert';
import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:path/path.dart' as path;

import 'line_age_report.dart';
import 'project_source.dart';

/// Surviving project-source lines bucketed by last-touched month.
class LastTouchedMonths(final ProjectSource projectSource) {
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Future<LineAgeReport> measure({
    void Function(LineAgeProgress progress)? onProgress,
  }) async {
    final countedFiles = projectSource.countedFiles;
    if (countedFiles.isEmpty) {
      throw StateError('No project source files found.');
    }

    final totalByMonth = <String, int>{};
    final linesByMonthAndFile = <String, Map<String, int>>{};

    for (var index = 0; index < countedFiles.length; index++) {
      if (_cancelled) {
        throw StateError('Line age analysis cancelled.');
      }
      final relativePath = path.relative(
        countedFiles[index].path,
        from: projectSource.gitRoot,
      );
      onProgress?.call(
        LineAgeProgress(
          completedFiles: index,
          totalFiles: countedFiles.length,
          currentRelativePath: relativePath,
        ),
      );
      _mergeFileCounts(
        relativePath: relativePath,
        fileCounts: await _lastTouchedCounts(relativePath),
        totalByMonth: totalByMonth,
        linesByMonthAndFile: linesByMonthAndFile,
      );
    }

    onProgress?.call(
      LineAgeProgress(
        completedFiles: countedFiles.length,
        totalFiles: countedFiles.length,
        currentRelativePath: '',
      ),
    );

    return _report(
      totalByMonth: totalByMonth,
      linesByMonthAndFile: linesByMonthAndFile,
      fileCount: countedFiles.length,
    );
  }

  void _mergeFileCounts({
    required String relativePath,
    required Map<String, int> fileCounts,
    required Map<String, int> totalByMonth,
    required Map<String, Map<String, int>> linesByMonthAndFile,
  }) {
    for (final entry in fileCounts.entries) {
      totalByMonth.update(
        entry.key,
        (count) => count + entry.value,
        ifAbsent: () => entry.value,
      );
      final monthFiles = linesByMonthAndFile.putIfAbsent(
        entry.key,
        () => <String, int>{},
      );
      monthFiles.update(
        relativePath,
        (count) => count + entry.value,
        ifAbsent: () => entry.value,
      );
    }
  }

  LineAgeReport _report({
    required Map<String, int> totalByMonth,
    required Map<String, Map<String, int>> linesByMonthAndFile,
    required int fileCount,
  }) {
    final sortedMonths = totalByMonth.keys.toList()..sort();
    final totalByFile = <String, int>{};
    for (final monthFiles in linesByMonthAndFile.values) {
      for (final entry in monthFiles.entries) {
        totalByFile.update(
          entry.key,
          (count) => count + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }
    final filesByTotal = totalByFile.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));

    return LineAgeReport(
      repoName: path.basename(projectSource.gitRoot),
      months: [
        for (final month in sortedMonths)
          _month(
            month,
            totalByMonth[month]!,
            linesByMonthAndFile[month] ?? const <String, int>{},
          ),
      ],
      totalLinesByFile: {
        for (final entry in filesByTotal) entry.key: entry.value,
      },
      totalLines: totalByMonth.values.fold(0, (sum, count) => sum + count),
      fileCount: fileCount,
    );
  }

  LineAgeMonth _month(
    String month,
    int totalLines,
    Map<String, int> fileCounts,
  ) {
    final ordered = fileCounts.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return LineAgeMonth(
      month: month,
      totalLines: totalLines,
      segments: [
        for (final entry in ordered)
          LineAgeSegment(file: entry.key, lineCount: entry.value),
      ],
    );
  }

  Future<Map<String, int>> _lastTouchedCounts(String relativePath) async {
    final process = await Process.run(
      'git',
      ['blame', '--line-porcelain', relativePath],
      workingDirectory: projectSource.gitRoot,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (process.exitCode != 0) return {};

    final counts = <String, int>{};
    for (final line in const LineSplitter().convert(process.stdout as String)) {
      if (!line.startsWith('committer-time ')) continue;
      final timestamp = int.tryParse(line.substring('committer-time '.length));
      if (timestamp == null) continue;
      final committedAt = DateTime.fromMillisecondsSinceEpoch(
        timestamp * 1000,
        isUtc: true,
      );
      counts.update(
        committedAt.yearMonthKey,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return counts;
  }
}
