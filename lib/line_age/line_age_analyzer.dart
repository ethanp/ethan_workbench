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

  Map<String, Object?> toJson() => {
    'file': file,
    'lineCount': lineCount,
  };

  factory LineAgeSegment.fromJson(Map<String, dynamic> json) {
    return LineAgeSegment(
      file: json['file'] as String,
      lineCount: json['lineCount'] as int,
    );
  }
}

/// All file segments for a single YYYY-MM bucket.
class LineAgeMonth {
  const LineAgeMonth({
    required this.month,
    required this.totalLines,
    required this.segments,
  });

  static const _shortMonthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final String month;
  final int totalLines;
  final List<LineAgeSegment> segments;

  int? get year => _yearMonthPart(0, 4);

  int? get monthNumber => _yearMonthPart(5, 7);

  int? _yearMonthPart(int start, int end) {
    if (month.length < 7 || month[4] != '-') return null;
    return int.tryParse(month.substring(start, end));
  }

  /// Axis tick without the year (`Feb`). Raw [month] if the key is malformed.
  String get shortMonthName {
    final number = monthNumber;
    if (number == null || number < 1 || number > 12) return month;
    return _shortMonthNames[number - 1];
  }

  bool get isEmpty => totalLines == 0;

  factory LineAgeMonth.empty(String month) => LineAgeMonth(
    month: month,
    totalLines: 0,
    segments: const [],
  );

  /// Inclusive YYYY-MM keys from [start] to [end]. Malformed keys stay as given.
  static List<String> keysFromTo(String start, String end) {
    final startMonth = LineAgeMonth.empty(start);
    final endMonth = LineAgeMonth.empty(end);
    if (startMonth.year == null ||
        startMonth.monthNumber == null ||
        endMonth.year == null ||
        endMonth.monthNumber == null) {
      return [start, if (end != start) end];
    }
    final keys = <String>[];
    var cursor = DateTime(startMonth.year!, startMonth.monthNumber!);
    final last = DateTime(endMonth.year!, endMonth.monthNumber!);
    while (!cursor.isAfter(last)) {
      keys.add(
        '${cursor.year.toString().padLeft(4, '0')}-'
        '${cursor.month.toString().padLeft(2, '0')}',
      );
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return keys;
  }

  Map<String, Object?> toJson() => {
    'month': month,
    'totalLines': totalLines,
    'segments': [for (final segment in segments) segment.toJson()],
  };

  factory LineAgeMonth.fromJson(Map<String, dynamic> json) {
    return LineAgeMonth(
      month: json['month'] as String,
      totalLines: json['totalLines'] as int,
      segments: [
        for (final segment in json['segments'] as List<dynamic>)
          LineAgeSegment.fromJson(segment as Map<String, dynamic>),
      ],
    );
  }
}

/// Contiguous months that share a calendar year — one x-axis year section.
class LineAgeYearBand {
  const LineAgeYearBand({
    required this.year,
    required this.firstMonthIndex,
    required this.lastMonthIndex,
  });

  final int year;
  final int firstMonthIndex;
  final int lastMonthIndex;
}

/// Full stacked histogram for a repo.
class LineAgeReport {
  const LineAgeReport({
    required this.repoName,
    required this.months,
    required this.totalLinesByFile,
    required this.totalLines,
    required this.fileCount,
  });

  final String repoName;
  final List<LineAgeMonth> months;

  /// Relative path → current line count, ordered largest-first.
  final Map<String, int> totalLinesByFile;
  final int totalLines;
  final int fileCount;

  List<String> get filesByTotalLines => totalLinesByFile.keys.toList();

  /// First-to-last months with empty slots so gaps stay on the x-axis.
  List<LineAgeMonth> get timelineMonths {
    if (months.isEmpty) return const [];
    final byKey = {for (final month in months) month.month: month};
    final sortedKeys = months.map((month) => month.month).toList()..sort();
    return [
      for (final key in LineAgeMonth.keysFromTo(sortedKeys.first, sortedKeys.last))
        byKey[key] ?? LineAgeMonth.empty(key),
    ];
  }

  /// Year sections on [timelineMonths], for x-axis grouping.
  List<LineAgeYearBand> get yearBands {
    final timeline = timelineMonths;
    if (timeline.isEmpty) return const [];
    final bands = <LineAgeYearBand>[];
    var bandStart = 0;
    var bandYear = timeline.first.year;
    for (var monthIndex = 1; monthIndex < timeline.length; monthIndex++) {
      final year = timeline[monthIndex].year;
      if (year == bandYear) continue;
      if (bandYear != null) {
        bands.add(
          LineAgeYearBand(
            year: bandYear,
            firstMonthIndex: bandStart,
            lastMonthIndex: monthIndex - 1,
          ),
        );
      }
      bandStart = monthIndex;
      bandYear = year;
    }
    if (bandYear != null) {
      bands.add(
        LineAgeYearBand(
          year: bandYear,
          firstMonthIndex: bandStart,
          lastMonthIndex: timeline.length - 1,
        ),
      );
    }
    return bands;
  }

  Map<String, Object?> toJson() => {
    'repoName': repoName,
    'totalLines': totalLines,
    'fileCount': fileCount,
    'totalLinesByFile': totalLinesByFile,
    'months': [for (final month in months) month.toJson()],
  };

  factory LineAgeReport.fromJson(Map<String, dynamic> json) {
    return LineAgeReport(
      repoName: json['repoName'] as String,
      totalLines: json['totalLines'] as int,
      fileCount: json['fileCount'] as int,
      totalLinesByFile: {
        for (final entry
            in (json['totalLinesByFile'] as Map<String, dynamic>).entries)
          entry.key: entry.value as int,
      },
      months: [
        for (final month in json['months'] as List<dynamic>)
          LineAgeMonth.fromJson(month as Map<String, dynamic>),
      ],
    );
  }
}

/// Analyzes Dart line age via `git blame --line-porcelain`.
///
/// [repoPath] may be any directory inside a git checkout (e.g. a Flutter app
/// under a monorepo). Analysis always covers the whole git root once found.
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

  /// Directory used to locate the git root (not necessarily the root itself).
  final String repoPath;
  final List<String> extraExcludeSuffixes;

  bool _cancelled = false;

  void cancel() => _cancelled = true;

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
    final startDirectory = Directory(repoPath);
    if (!startDirectory.existsSync()) {
      throw StateError('Not a directory: $repoPath');
    }
    final gitRoot = findGitRoot(repoPath);
    if (gitRoot == null) {
      throw StateError('Not inside a git repository: $repoPath');
    }

    final dartFiles = listDartFiles(
      gitRoot,
      extraExcludeSuffixes: extraExcludeSuffixes,
    );
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
      final relativePath = path.relative(file.path, from: gitRoot);
      onProgress?.call(
        LineAgeProgress(
          completedFiles: index,
          totalFiles: dartFiles.length,
          currentRelativePath: relativePath,
        ),
      );

      final fileCounts = await _blameFile(
        relativePath,
        workingDirectory: gitRoot,
      );
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
      repoName: path.basename(gitRoot),
      months: months,
      totalLinesByFile: {
        for (final entry in filesByTotal) entry.key: entry.value,
      },
      totalLines: totalByMonth.values.fold(0, (sum, count) => sum + count),
      fileCount: dartFiles.length,
    );
  }

  /// Non-generated Dart sources under [scanRoot], matching analyze exclusions.
  static List<File> listDartFiles(
    String scanRoot, {
    List<String> extraExcludeSuffixes = const [],
  }) {
    final excludes = [...generatedSuffixes, ...extraExcludeSuffixes];
    final dartFiles = <File>[];
    final queue = Queue<Directory>()..add(Directory(scanRoot));
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
          if (name == '.git') continue;
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

  Future<Map<String, int>> _blameFile(
    String relativePath, {
    required String workingDirectory,
  }) async {
    final process = await Process.run(
      'git',
      ['blame', '--line-porcelain', relativePath],
      workingDirectory: workingDirectory,
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

