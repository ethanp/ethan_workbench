import 'dart:convert';
import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';

import 'line_age_report.dart';
import 'project_source.dart';

/// Project size at month-end for closed months, and as of today for this month.
class ProjectSizeThroughMonths(final ProjectSource projectSource) {
  bool _cancelled = false;
  String? _emptyTreeHash;

  void cancel() => _cancelled = true;

  Future<ProjectSizeByMonth> along(Iterable<String> yearMonths) async {
    final currentYearMonth = DateTime.now().yearMonthKey;
    final linesByYearMonth = <String, int>{};
    for (final yearMonth in yearMonths) {
      if (_cancelled) {
        throw StateError('Line age analysis cancelled.');
      }
      linesByYearMonth[yearMonth] = yearMonth == currentYearMonth
          ? projectSource.lineCountAsOfToday
          : await _sizeAtMonthEnd(yearMonth);
    }
    return ProjectSizeByMonth(linesByYearMonth: linesByYearMonth);
  }

  Future<int> _sizeAtMonthEnd(String yearMonth) async {
    final commit = await _lastCommitOnOrBefore(_monthEnd(yearMonth));
    if (commit == null) return 0;
    return _projectSourceLinesAt(commit);
  }

  DateTime _monthEnd(String yearMonth) {
    final year = int.parse(yearMonth.substring(0, 4));
    final month = int.parse(yearMonth.substring(5, 7));
    return DateTime(year, month + 1, 0, 23, 59, 59);
  }

  Future<String?> _lastCommitOnOrBefore(DateTime monthEnd) async {
    final process = await Process.run(
      'git',
      ['rev-list', '-1', '--before=${_gitTimestamp(monthEnd)}', 'HEAD'],
      workingDirectory: projectSource.gitRoot,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (process.exitCode != 0) return null;
    final commit = (process.stdout as String).trim();
    if (commit.isEmpty) return null;
    return commit;
  }

  String _gitTimestamp(DateTime monthEnd) {
    final year = monthEnd.year.toString().padLeft(4, '0');
    final month = monthEnd.month.toString().padLeft(2, '0');
    final day = monthEnd.day.toString().padLeft(2, '0');
    final hour = monthEnd.hour.toString().padLeft(2, '0');
    final minute = monthEnd.minute.toString().padLeft(2, '0');
    final second = monthEnd.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  Future<int> _projectSourceLinesAt(String commit) async {
    final emptyTree = await _emptyTree();
    final process = await Process.run(
      'git',
      ['diff', '--numstat', emptyTree, commit, '--', '*.dart', '*.swift'],
      workingDirectory: projectSource.gitRoot,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (process.exitCode != 0) return 0;
    var lineCount = 0;
    for (final row in const LineSplitter().convert(process.stdout as String)) {
      lineCount += _addedLinesIfProjectSource(row);
    }
    return lineCount;
  }

  int _addedLinesIfProjectSource(String row) {
    if (row.isEmpty) return 0;
    final tab = row.indexOf('\t');
    if (tab < 0) return 0;
    final secondTab = row.indexOf('\t', tab + 1);
    if (secondTab < 0) return 0;
    final added = row.substring(0, tab);
    if (added == '-') return 0;
    final addedLines = int.tryParse(added);
    if (addedLines == null) return 0;
    final relativePath = row.substring(secondTab + 1);
    if (!projectSource.includes(relativePath)) return 0;
    return addedLines;
  }

  Future<String> _emptyTree() async {
    final cached = _emptyTreeHash;
    if (cached != null) return cached;
    final process = await Process.start(
      'git',
      ['hash-object', '-t', 'tree', '--stdin'],
      workingDirectory: projectSource.gitRoot,
    );
    await process.stdin.close();
    final hash = (await process.stdout.transform(utf8.decoder).join()).trim();
    final exitCode = await process.exitCode;
    if (exitCode != 0 || hash.isEmpty) {
      throw StateError('Could not resolve the empty git tree.');
    }
    _emptyTreeHash = hash;
    return hash;
  }
}
