import 'package:ethan_workbench/line_age/line_age_directory_groups.dart';
import 'package:ethan_workbench/line_age/line_age_repo_groups.dart';
import 'package:ethan_workbench/line_age/line_age_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('key is the repo prefix', () {
    expect(LineAgeRepoGroups.keyForFile('workouts/lib/a.dart'), 'workouts');
    expect(LineAgeRepoGroups.keyForFile('ethan_utils/src/foo.dart'), 'ethan_utils');
  });

  test('legend keeps every repo and does not fold into other', () {
    final files = <String, int>{
      for (var index = 0; index < 12; index++)
        'repo$index/lib/a.dart': 100 - index,
    };
    final report = LineAgeReport(
      repoName: LineAgeReport.flutterFleetName,
      months: [
        LineAgeMonth(
          month: '2026-01',
          totalLines: files.values.fold(0, (sum, count) => sum + count),
          segments: [
            for (final entry in files.entries)
              LineAgeSegment(file: entry.key, lineCount: entry.value),
          ],
        ),
      ],
      totalLinesByFile: files,
      totalLines: files.values.fold(0, (sum, count) => sum + count),
      fileCount: files.length,
    );

    final legend = LineAgeRepoGroups.legendFor(report);
    expect(legend.orderedKeys, hasLength(12));
    expect(legend.orderedKeys.first, 'repo0');
    expect(legend.orderedKeys.contains(LineAgeDirectoryGroups.otherKey), isFalse);
    expect(legend.resolveKey('repo11/lib/a.dart'), 'repo11');
  });
}
