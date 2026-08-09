import 'package:ethan_workbench/line_age/line_age_analyzer.dart';
import 'package:ethan_workbench/line_age/line_age_directory_groups.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('directory key uses parent path capped at two segments', () {
    expect(LineAgeDirectoryGroups.keyForFile('main.dart'), '(repo root)');
    expect(LineAgeDirectoryGroups.keyForFile('lib/main.dart'), 'lib');
    expect(
      LineAgeDirectoryGroups.keyForFile('lib/screens/home.dart'),
      'lib/screens',
    );
    expect(
      LineAgeDirectoryGroups.keyForFile('lib/screens/home/body.dart'),
      'lib/screens',
    );
    expect(
      LineAgeDirectoryGroups.keyForFile('apps/music_listen/lib/main.dart'),
      'apps/music_listen',
    );
  });

  test('legend keeps top directories distinct and folds the rest into other', () {
    final files = <String, int>{
      for (var index = 0; index < 14; index++)
        'pkg$index/lib/a.dart': 100 - index,
    };
    final report = LineAgeReport(
      repoName: 'demo',
      months: [
        LineAgeMonth(
          month: '2026-01',
          totalLines: files.values.fold(0, (sum, n) => sum + n),
          segments: [
            for (final entry in files.entries)
              LineAgeSegment(file: entry.key, lineCount: entry.value),
          ],
        ),
      ],
      totalLinesByFile: files,
      totalLines: files.values.fold(0, (sum, n) => sum + n),
      fileCount: files.length,
    );

    final legend = LineAgeDirectoryGroups.legendFor(report);
    expect(legend.orderedKeys.length, 11); // 10 + other
    expect(legend.orderedKeys.last, LineAgeDirectoryGroups.otherKey);
    expect(
      legend.resolveKey('pkg12/lib/a.dart'),
      LineAgeDirectoryGroups.otherKey,
    );
    expect(legend.colorForKey('pkg0/lib'), isNot(const Color(0xFF64748B)));
  });
}
