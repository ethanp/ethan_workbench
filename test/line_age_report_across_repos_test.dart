import 'package:ethan_workbench/line_age/line_age_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('acrossRepos prefixes files and sums months and project size', () {
    final workouts = LineAgeReport(
      repoName: 'workouts',
      months: [
        LineAgeMonth(
          month: '2026-01',
          totalLines: 10,
          segments: const [
            LineAgeSegment(file: 'lib/a.dart', lineCount: 10),
          ],
        ),
      ],
      totalLinesByFile: const {'lib/a.dart': 10},
      totalLines: 10,
      fileCount: 1,
      projectSizeByMonth: const ProjectSizeByMonth(
        linesByYearMonth: {'2026-01': 40, '2026-02': 42},
      ),
    );
    final utils = LineAgeReport(
      repoName: 'ethan_utils',
      months: [
        LineAgeMonth(
          month: '2026-01',
          totalLines: 3,
          segments: const [
            LineAgeSegment(file: 'lib/a.dart', lineCount: 3),
          ],
        ),
        LineAgeMonth(
          month: '2026-03',
          totalLines: 5,
          segments: const [
            LineAgeSegment(file: 'lib/b.dart', lineCount: 5),
          ],
        ),
      ],
      totalLinesByFile: const {'lib/a.dart': 3, 'lib/b.dart': 5},
      totalLines: 8,
      fileCount: 2,
      projectSizeByMonth: const ProjectSizeByMonth(
        linesByYearMonth: {'2026-01': 20},
      ),
    );

    final fleet = LineAgeReport.acrossRepos([workouts, utils]);

    expect(fleet.repoName, LineAgeReport.flutterFleetName);
    expect(fleet.totalLines, 18);
    expect(fleet.fileCount, 3);
    expect(fleet.totalLinesByFile['workouts/lib/a.dart'], 10);
    expect(fleet.totalLinesByFile['ethan_utils/lib/b.dart'], 5);
    expect(fleet.projectSizeByMonth.at('2026-01'), 60);
    expect(fleet.projectSizeByMonth.at('2026-02'), 42);

    final january = fleet.months.singleWhere((month) => month.month == '2026-01');
    expect(january.totalLines, 13);
    expect(
      january.segments.map((segment) => segment.file),
      containsAll(['workouts/lib/a.dart', 'ethan_utils/lib/a.dart']),
    );
  });

  test('acrossRepos of none is an empty Flutter report', () {
    final fleet = LineAgeReport.acrossRepos(const []);
    expect(fleet.repoName, 'Flutter');
    expect(fleet.months, isEmpty);
    expect(fleet.totalLines, 0);
    expect(fleet.fileCount, 0);
  });
}
