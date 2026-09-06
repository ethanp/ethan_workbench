import 'line_age_directory_groups.dart';
import 'line_age_report.dart';

/// Maps fleet-prefixed files (`repo/lib/foo.dart`) into one color per repo.
abstract final class LineAgeRepoGroups() {
  /// First path segment — the repo name prefix from [LineAgeReport.acrossRepos].
  static String keyForFile(String relativeFilePath) {
    final normalized = relativeFilePath.replaceAll('\\', '/');
    final slash = normalized.indexOf('/');
    if (slash <= 0) return normalized;
    return normalized.substring(0, slash);
  }

  static LineAgeDirectoryLegend legendFor(LineAgeReport report) {
    final totals = <String, int>{};
    for (final entry in report.totalLinesByFile.entries) {
      final key = keyForFile(entry.key);
      totals.update(
        key,
        (count) => count + entry.value,
        ifAbsent: () => entry.value,
      );
    }

    final ranked = totals.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    final orderedKeys = [for (final entry in ranked) entry.key];
    final palette = LineAgeDirectoryGroups.palette;

    return LineAgeDirectoryLegend(
      orderedKeys: orderedKeys,
      colors: {
        for (var index = 0; index < orderedKeys.length; index++)
          orderedKeys[index]: palette[index % palette.length],
      },
      totalLinesByKey: {for (final entry in ranked) entry.key: entry.value},
      resolveKey: keyForFile,
    );
  }
}
