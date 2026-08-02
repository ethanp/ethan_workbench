import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Progress while blaming files in a repo.
class LineAgeProgress {
  const LineAgeProgress({
    required this.completedFiles,
    required this.totalFiles,
    required this.currentRelativePath,
  });

  final int completedFiles;
  final int totalFiles;
  final String currentRelativePath;

  double get fraction =>
      totalFiles == 0 ? 0 : completedFiles / totalFiles;
}

/// One file's contribution within a month bar.
class LineAgeSegment {
  const LineAgeSegment({required this.file, required this.lineCount});

  final String file;
  final int lineCount;
}

/// All file segments for a single YYYY-MM bucket.
class LineAgeMonth {
  const LineAgeMonth({
    required this.month,
    required this.totalLines,
    required this.segments,
  });

  final String month;
  final int totalLines;
  final List<LineAgeSegment> segments;
}

/// Full stacked histogram for a repo.
class LineAgeReport {
  const LineAgeReport({
    required this.repoName,
    required this.months,
    required this.filesByTotalLines,
    required this.totalLines,
    required this.fileCount,
  });

  final String repoName;
  final List<LineAgeMonth> months;
  final List<String> filesByTotalLines;
  final int totalLines;
  final int fileCount;
}

/// Analyzes Dart line age via `git blame --line-porcelain`.
class LineAgeAnalyzer {
  static const generatedSuffixes = [
    '.g.dart',
    '.freezed.dart',
    '.gr.dart',
    '.gen.dart',
    '.mocks.dart',
  ];

  static const skipDirectoryNames = {'.dart_tool', 'build', '.symlinks'};

  LineAgeAnalyzer({
    required this.repoPath,
    this.extraExcludeSuffixes = const [],
  });

  final String repoPath;
  final List<String> extraExcludeSuffixes;

  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Future<LineAgeReport> analyze({
    void Function(LineAgeProgress progress)? onProgress,
  }) async {
    final repo = Directory(repoPath);
    if (!repo.existsSync()) {
      throw StateError('Not a directory: $repoPath');
    }
    if (!Directory(path.join(repoPath, '.git')).existsSync()) {
      throw StateError('Not a git repository: $repoPath');
    }

    final dartFiles = _findDartFiles();
    if (dartFiles.isEmpty) {
      throw StateError('No non-generated Dart files found.');
    }

    final totalByMonth = <String, int>{};
    final linesByMonthAndFile = <String, Map<String, int>>{};

    for (var index = 0; index < dartFiles.length; index++) {
      if (_cancelled) {
        throw StateError('Line age analysis cancelled.');
      }
      final file = dartFiles[index];
      final relativePath = path.relative(file.path, from: repoPath);
      onProgress?.call(
        LineAgeProgress(
          completedFiles: index,
          totalFiles: dartFiles.length,
          currentRelativePath: relativePath,
        ),
      );

      final fileCounts = await _blameFile(relativePath);
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

    onProgress?.call(
      LineAgeProgress(
        completedFiles: dartFiles.length,
        totalFiles: dartFiles.length,
        currentRelativePath: '',
      ),
    );

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

    final months = <LineAgeMonth>[];
    for (final month in sortedMonths) {
      final fileCounts = linesByMonthAndFile[month] ?? const <String, int>{};
      final ordered = fileCounts.entries.toList()
        ..sort((left, right) => right.value.compareTo(left.value));
      months.add(
        LineAgeMonth(
          month: month,
          totalLines: totalByMonth[month]!,
          segments: [
            for (final entry in ordered)
              LineAgeSegment(file: entry.key, lineCount: entry.value),
          ],
        ),
      );
    }

    return LineAgeReport(
      repoName: path.basename(repoPath),
      months: months,
      filesByTotalLines: [for (final entry in filesByTotal) entry.key],
      totalLines: totalByMonth.values.fold(0, (sum, count) => sum + count),
      fileCount: dartFiles.length,
    );
  }

  List<File> _findDartFiles() {
    final excludes = [...generatedSuffixes, ...extraExcludeSuffixes];
    final dartFiles = <File>[];
    final queue = Queue<Directory>()..add(Directory(repoPath));
    while (queue.isNotEmpty) {
      final directory = queue.removeFirst();
      late final List<FileSystemEntity> children;
      try {
        children = directory.listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final entity in children) {
        final name = path.basename(entity.path);
        if (entity is Directory) {
          if (skipDirectoryNames.contains(name)) continue;
          queue.add(entity);
          continue;
        }
        if (entity is! File) continue;
        if (!name.endsWith('.dart')) continue;
        if (excludes.any(name.endsWith)) continue;
        dartFiles.add(entity);
      }
    }
    dartFiles.sort((left, right) => left.path.compareTo(right.path));
    return dartFiles;
  }

  Future<Map<String, int>> _blameFile(String relativePath) async {
    final process = await Process.run(
      'git',
      ['blame', '--line-porcelain', relativePath],
      workingDirectory: repoPath,
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
      final bucket =
          '${committedAt.year.toString().padLeft(4, '0')}-'
          '${committedAt.month.toString().padLeft(2, '0')}';
      counts.update(bucket, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }
}
