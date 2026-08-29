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

  test('timeline months fill empty slots between first and last', () {
    expect(_report([]).timelineMonths, isEmpty);

    final filled = _report(['2026-01', '2026-04']);
    expect(
      filled.timelineMonths.map((month) => month.month),
      ['2026-01', '2026-02', '2026-03', '2026-04'],
    );
    expect(filled.timelineMonths[0].isEmpty, isFalse);
    expect(filled.timelineMonths[1].isEmpty, isTrue);
    expect(filled.timelineMonths[2].isEmpty, isTrue);
    expect(filled.timelineMonths[3].isEmpty, isFalse);
  });

  test('timeline months wrap across a year boundary', () {
    expect(
      LineAgeMonth.keysFromTo('2025-11', '2026-02'),
      ['2025-11', '2025-12', '2026-01', '2026-02'],
    );
  });

  test('year bands group contiguous timeline months including empty slots', () {
    expect(_report([]).yearBands, isEmpty);

    final singleYear = _report(['2026-01', '2026-08']);
    expect(singleYear.yearBands, hasLength(1));
    expect(singleYear.yearBands.single.year, 2026);
    expect(singleYear.yearBands.single.firstMonthIndex, 0);
    expect(singleYear.yearBands.single.lastMonthIndex, 7);

    final multiYear = _report([
      '2021-02',
      '2021-04',
      '2022-01',
      '2026-07',
      '2026-08',
    ]);
    expect(multiYear.yearBands.map((band) => band.year), [
      2021,
      2022,
      2023,
      2024,
      2025,
      2026,
    ]);
    expect(multiYear.yearBands[0].firstMonthIndex, 0);
    expect(multiYear.yearBands[0].lastMonthIndex, 10);
    expect(multiYear.yearBands[1].firstMonthIndex, 11);
    expect(multiYear.yearBands[1].lastMonthIndex, 22);
    expect(multiYear.yearBands[5].firstMonthIndex, 59);
    expect(multiYear.yearBands[5].lastMonthIndex, 66);
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
