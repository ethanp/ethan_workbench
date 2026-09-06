import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:ethan_workbench/line_age/last_touched_months.dart';
import 'package:ethan_workbench/line_age/project_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('last-touched months bucket a Swift file’s surviving lines', () async {
    final root = await _committedProjectSource();
    final report = await LastTouchedMonths(ProjectSource.at(root.path)).measure();

    expect(report.totalLinesByFile.keys, contains('lib/a.dart'));
    expect(
      report.totalLinesByFile.keys,
      contains('macos/Runner/AppDelegate.swift'),
    );
    expect(report.totalLines, 3);
    expect(report.fileCount, 2);
    expect(report.months, isNotEmpty);
    expect(report.months.first.month, DateTime.utc(2025, 1, 15).yearMonthKey);
  });

  test('uncommitted extra lines on a tracked file count in this month', () async {
    final root = await _committedProjectSource();
    File(path.join(root.path, 'lib', 'a.dart')).writeAsStringSync(
      'class A {}\nclass B {}\n',
    );

    final report = await LastTouchedMonths(ProjectSource.at(root.path)).measure();
    final thisMonth = report.months.singleWhere(
      (month) => month.month == DateTime.now().toUtc().yearMonthKey,
    );
    expect(report.totalLines, 4);
    expect(
      report.months.singleWhere((month) => month.month == '2025-01').totalLines,
      3,
    );
    expect(thisMonth.totalLines, 1);
    expect(thisMonth.segments.single.file, 'lib/a.dart');
  });

  test('untracked project-source files count as last-touched this month', () async {
    final root = await _committedProjectSource();
    File(path.join(root.path, 'lib', 'extra.dart')).writeAsStringSync(
      'class Extra {}\nclass ExtraTwo {}\n',
    );

    final report = await LastTouchedMonths(ProjectSource.at(root.path)).measure();
    final thisMonth = DateTime.now().toUtc().yearMonthKey;
    expect(report.fileCount, 3);
    expect(report.totalLines, 5);
    expect(report.totalLinesByFile['lib/extra.dart'], 2);
    expect(
      report.months.singleWhere((month) => month.month == '2025-01').totalLines,
      3,
    );
    expect(
      report.months.singleWhere((month) => month.month == thisMonth).totalLines,
      2,
    );
  });
}

Future<Directory> _committedProjectSource() async {
  final root = Directory.systemTemp.createTempSync('last_touched_');
  addTearDown(() => root.deleteSync(recursive: true));
  await _git(root, ['init', '-b', 'main']);
  await _git(root, ['config', 'user.email', 'test@example.com']);
  await _git(root, ['config', 'user.name', 'Test']);
  File(path.join(root.path, 'lib', 'a.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('class A {}\n');
  File(path.join(root.path, 'macos', 'Runner', 'AppDelegate.swift'))
    ..createSync(recursive: true)
    ..writeAsStringSync('import Cocoa\nimport FlutterMacOS\n');
  await _git(root, ['add', '.']);
  await _git(
    root,
    ['commit', '-m', 'init'],
    environment: {
      'GIT_AUTHOR_DATE': '2025-01-15T12:00:00',
      'GIT_COMMITTER_DATE': '2025-01-15T12:00:00',
    },
  );
  return root;
}

Future<void> _git(
  Directory root,
  List<String> args, {
  Map<String, String>? environment,
}) async {
  final process = await Process.run(
    'git',
    args,
    workingDirectory: root.path,
    environment: {...Platform.environment, ...?environment},
  );
  expect(process.exitCode, 0, reason: '${args.join(' ')}: ${process.stderr}');
}
