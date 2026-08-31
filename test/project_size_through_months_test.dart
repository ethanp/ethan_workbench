import 'dart:convert';
import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:ethan_workbench/line_age/line_age_report.dart';
import 'package:ethan_workbench/line_age/project_size_through_months.dart';
import 'package:ethan_workbench/line_age/project_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test(
    'project size at month-end uses the last commit on or before that month',
    () async {
      final root = await _historyWithTwoClosedMonths();
      final sizes = await ProjectSizeThroughMonths(
        ProjectSource.at(root.path),
      ).along(['2025-01', '2025-02']);

      expect(sizes.at('2025-01'), 3);
      expect(sizes.at('2025-02'), 5);
    },
  );

  test('project size as of today uses the working tree', () async {
    final root = await _historyWithTwoClosedMonths();
    File(path.join(root.path, 'lib', 'extra.dart')).writeAsStringSync(
      'class Extra {}\nclass ExtraTwo {}\n',
    );

    final current = DateTime.now().yearMonthKey;
    final sizes = await ProjectSizeThroughMonths(
      ProjectSource.at(root.path),
    ).along([current]);

    expect(sizes.at(current), 7);
  });

  test('LineAgeReport JSON round-trips project size by month', () {
    final report = LineAgeReport(
      repoName: 'demo',
      months: [
        LineAgeMonth(month: '2025-01', totalLines: 2, segments: const []),
      ],
      totalLinesByFile: const {},
      totalLines: 2,
      fileCount: 1,
      projectSizeByMonth: const ProjectSizeByMonth(
        linesByYearMonth: {'2025-01': 40, '2025-02': 44},
      ),
    );

    final restored = LineAgeReport.fromJson(
      jsonDecode(jsonEncode(report.toJson())) as Map<String, dynamic>,
    );
    expect(restored.projectSizeByMonth.at('2025-01'), 40);
    expect(restored.projectSizeByMonth.at('2025-02'), 44);
    expect(restored.projectSizeByMonth.peak, 44);
  });
}

Future<Directory> _historyWithTwoClosedMonths() async {
  final root = Directory.systemTemp.createTempSync('project_size_');
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
    ['commit', '-m', 'january'],
    environment: {
      'GIT_AUTHOR_DATE': '2025-01-15T12:00:00',
      'GIT_COMMITTER_DATE': '2025-01-15T12:00:00',
    },
  );

  File(path.join(root.path, 'lib', 'a.dart')).writeAsStringSync(
    'class A {}\nclass B {}\nclass C {}\n',
  );
  await _git(root, ['add', '.']);
  await _git(
    root,
    ['commit', '-m', 'february'],
    environment: {
      'GIT_AUTHOR_DATE': '2025-02-10T12:00:00',
      'GIT_COMMITTER_DATE': '2025-02-10T12:00:00',
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
