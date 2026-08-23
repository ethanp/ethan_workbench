import 'package:ethan_workbench/line_age/line_age_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('short month name drops the year from YYYY-MM', () {
    final february = _month('2021-02');
    expect(february.year, 2021);
    expect(february.monthNumber, 2);
    expect(february.shortMonthName, 'Feb');
  });

  test('malformed month key keeps the raw label', () {
    final malformed = _month('sometime');
    expect(malformed.year, isNull);
    expect(malformed.shortMonthName, 'sometime');
  });

  test('year bands group contiguous months and skip empty reports', () {
    expect(_report([]).yearBands, isEmpty);

    final singleYear = _report(['2026-01', '2026-08']);
    expect(singleYear.yearBands, hasLength(1));
    expect(singleYear.yearBands.single.year, 2026);
    expect(singleYear.yearBands.single.firstMonthIndex, 0);
    expect(singleYear.yearBands.single.lastMonthIndex, 1);

    final multiYear = _report([
      '2021-02',
      '2021-04',
      '2022-01',
      '2026-07',
      '2026-08',
    ]);
    expect(multiYear.yearBands.map((band) => band.year), [2021, 2022, 2026]);
    expect(multiYear.yearBands[0].firstMonthIndex, 0);
    expect(multiYear.yearBands[0].lastMonthIndex, 1);
    expect(multiYear.yearBands[1].firstMonthIndex, 2);
    expect(multiYear.yearBands[1].lastMonthIndex, 2);
    expect(multiYear.yearBands[2].firstMonthIndex, 3);
    expect(multiYear.yearBands[2].lastMonthIndex, 4);
  });
}

LineAgeMonth _month(String month) => LineAgeMonth(
  month: month,
  totalLines: 1,
  segments: const [],
);

LineAgeReport _report(List<String> months) => LineAgeReport(
  repoName: 'test',
  months: [for (final month in months) _month(month)],
  totalLinesByFile: const {},
  totalLines: months.length,
  fileCount: 1,
);
