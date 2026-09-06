import 'package:ethan_utils/ethan_utils.dart';

/// Progress while measuring last-touched months.
class const LineAgeProgress({
  required final int completedFiles,
  required final int totalFiles,
  required final String currentRelativePath,
}) {
  double get fraction => totalFiles == 0 ? 0 : completedFiles / totalFiles;
}

/// One file's contribution within a month bar.
class const LineAgeSegment({
  required final String file,
  required final int lineCount,
}) {
  Map<String, Object?> toJson() => {'file': file, 'lineCount': lineCount};

  factory fromJson(Map<String, dynamic> json) {
    return LineAgeSegment(
      file: json['file'] as String,
      lineCount: json['lineCount'] as int,
    );
  }
}

/// All file segments for a single YYYY-MM last-touched bucket.
class const LineAgeMonth({
  required final String month,
  required final int totalLines,
  required final List<LineAgeSegment> segments,
}) {
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

  factory empty(String month) =>
      LineAgeMonth(month: month, totalLines: 0, segments: const []);

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
      keys.add(cursor.yearMonthKey);
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return keys;
  }

  static String laterYearMonth(String left, String right) =>
      left.compareTo(right) >= 0 ? left : right;

  Map<String, Object?> toJson() => {
    'month': month,
    'totalLines': totalLines,
    'segments': [for (final segment in segments) segment.toJson()],
  };

  factory fromJson(Map<String, dynamic> json) {
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
class const LineAgeYearBand({
  required final int year,
  required final int firstMonthIndex,
  required final int lastMonthIndex,
});

/// Project source line counts keyed by YYYY-MM (month-end, or as of today).
class const ProjectSizeByMonth({
  final Map<String, int> linesByYearMonth = const {},
}) {
  int? at(String yearMonth) => linesByYearMonth[yearMonth];

  int get peak {
    if (linesByYearMonth.isEmpty) return 0;
    return linesByYearMonth.values.reduce(
      (left, right) => left > right ? left : right,
    );
  }

  Map<String, Object?> toJson() => {
    for (final entry in linesByYearMonth.entries) entry.key: entry.value,
  };

  factory fromJson(Object? json) {
    if (json is! Map) return const ProjectSizeByMonth();
    return ProjectSizeByMonth(
      linesByYearMonth: {
        for (final entry in json.entries)
          entry.key.toString(): (entry.value as num).toInt(),
      },
    );
  }
}

/// Full stacked histogram plus project size through the same months.
class const LineAgeReport({
  required final String repoName,
  required final List<LineAgeMonth> months,

  /// Relative path → current line count, ordered largest-first.
  required final Map<String, int> totalLinesByFile,
  required final int totalLines,
  required final int fileCount,
  final ProjectSizeByMonth projectSizeByMonth = const ProjectSizeByMonth(),
}) {
  List<String> get filesByTotalLines => totalLinesByFile.keys.toList();

  /// First last-touched month through the later of last last-touched and today.
  List<LineAgeMonth> get timelineMonths {
    if (months.isEmpty) return const [];
    final byKey = {for (final month in months) month.month: month};
    final sortedKeys = months.map((month) => month.month).toList()..sort();
    final lastKey = LineAgeMonth.laterYearMonth(
      sortedKeys.last,
      DateTime.now().yearMonthKey,
    );
    return [
      for (final key in LineAgeMonth.keysFromTo(sortedKeys.first, lastKey))
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

  LineAgeReport withProjectSize(ProjectSizeByMonth projectSizeByMonth) {
    return LineAgeReport(
      repoName: repoName,
      months: months,
      totalLinesByFile: totalLinesByFile,
      totalLines: totalLines,
      fileCount: fileCount,
      projectSizeByMonth: projectSizeByMonth,
    );
  }

  Map<String, Object?> toJson() => {
    'repoName': repoName,
    'totalLines': totalLines,
    'fileCount': fileCount,
    'totalLinesByFile': totalLinesByFile,
    'months': [for (final month in months) month.toJson()],
    'projectSizeByMonth': projectSizeByMonth.toJson(),
  };

  factory fromJson(Map<String, dynamic> json) {
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
      projectSizeByMonth: ProjectSizeByMonth.fromJson(
        json['projectSizeByMonth'],
      ),
    );
  }

  static const flutterFleetName = 'Flutter';

  /// One report for a Flutter fleet: files prefixed with each [repoName].
  factory acrossRepos(List<LineAgeReport> reports) {
    if (reports.isEmpty) {
      return const LineAgeReport(
        repoName: flutterFleetName,
        months: [],
        totalLinesByFile: {},
        totalLines: 0,
        fileCount: 0,
      );
    }
    return LineAgeReport(
      repoName: flutterFleetName,
      months: _monthsAcrossRepos(reports),
      totalLinesByFile: _prefixedTotalsByFile(reports),
      totalLines: reports.fold(0, (sum, report) => sum + report.totalLines),
      fileCount: reports.fold(0, (sum, report) => sum + report.fileCount),
      projectSizeByMonth: _summedProjectSize(reports),
    );
  }

  static String _prefixedFile(String repoName, String relativeFilePath) =>
      '$repoName/$relativeFilePath';

  static List<LineAgeMonth> _monthsAcrossRepos(List<LineAgeReport> reports) {
    final segmentsByMonth = <String, List<LineAgeSegment>>{};
    final totalsByMonth = <String, int>{};
    for (final report in reports) {
      for (final month in report.months) {
        totalsByMonth.update(
          month.month,
          (count) => count + month.totalLines,
          ifAbsent: () => month.totalLines,
        );
        segmentsByMonth
            .putIfAbsent(month.month, () => [])
            .addAll([
              for (final segment in month.segments)
                LineAgeSegment(
                  file: _prefixedFile(report.repoName, segment.file),
                  lineCount: segment.lineCount,
                ),
            ]);
      }
    }
    final monthKeys = totalsByMonth.keys.toList()..sort();
    return [
      for (final month in monthKeys)
        LineAgeMonth(
          month: month,
          totalLines: totalsByMonth[month]!,
          segments: segmentsByMonth[month]!,
        ),
    ];
  }

  static Map<String, int> _prefixedTotalsByFile(List<LineAgeReport> reports) {
    final totals = <String, int>{
      for (final report in reports)
        for (final entry in report.totalLinesByFile.entries)
          _prefixedFile(report.repoName, entry.key): entry.value,
    };
    final ranked = totals.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return {for (final entry in ranked) entry.key: entry.value};
  }

  static ProjectSizeByMonth _summedProjectSize(List<LineAgeReport> reports) {
    final linesByYearMonth = <String, int>{};
    for (final report in reports) {
      for (final entry in report.projectSizeByMonth.linesByYearMonth.entries) {
        linesByYearMonth.update(
          entry.key,
          (count) => count + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }
    return ProjectSizeByMonth(linesByYearMonth: linesByYearMonth);
  }
}
