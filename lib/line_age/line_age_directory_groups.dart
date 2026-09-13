import 'package:flutter/material.dart';

import '../ui/workbench_action_accents.dart';
import 'line_age_report.dart';

/// Maps files into directory buckets for stacked bars.
///
/// Uses the file's parent path, capped at three segments so feature and
/// service folders stay distinct (`lib/features/cardio`, `lib/services/repositories`)
/// without exploding into one color per leaf folder.
abstract final class LineAgeDirectoryGroups() {
  static const otherKey = 'other directories';
  static const maxDistinctDirectories = 10;

  static const palette = <Color>[
    WorkbenchActionAccents.lineAge,
    Color(0xFF60A5FA),
    Color(0xFF2DD4BF),
    Color(0xFFF472B6),
    Color(0xFFFBBF24),
    Color(0xFF818CF8),
    Color(0xFF34D399),
    Color(0xFFFB923C),
    Color(0xFF22D3EE),
    Color(0xFFE879F9),
  ];

  static const otherColor = Color(0xFF64748B);

  /// Parent directory of [relativeFilePath], at most three path segments.
  static String keyForFile(String relativeFilePath) {
    final normalized = relativeFilePath.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    if (slash <= 0) return '(repo root)';
    final dir = normalized.substring(0, slash);
    final segments = dir.split('/');
    if (segments.length <= 3) return dir;
    return '${segments[0]}/${segments[1]}/${segments[2]}';
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

    final distinct = <String>[];
    var otherTotal = 0;
    for (final entry in ranked) {
      if (distinct.length < maxDistinctDirectories) {
        distinct.add(entry.key);
      } else {
        otherTotal += entry.value;
      }
    }

    final orderedKeys = [...distinct, if (otherTotal > 0) otherKey];

    final colors = <String, Color>{
      for (var index = 0; index < distinct.length; index++)
        distinct[index]: palette[index % palette.length],
      if (otherTotal > 0) otherKey: otherColor,
    };

    final totalsByKey = <String, int>{
      for (final key in distinct) key: totals[key]!,
      if (otherTotal > 0) otherKey: otherTotal,
    };

    final distinctSet = distinct.toSet();
    return LineAgeDirectoryLegend(
      orderedKeys: orderedKeys,
      colors: colors,
      totalLinesByKey: totalsByKey,
      resolveKey: (file) {
        final key = keyForFile(file);
        return distinctSet.contains(key) ? key : otherKey;
      },
    );
  }
}

class const LineAgeDirectoryLegend({
  /// Largest directories first; [LineAgeDirectoryGroups.otherKey] last when used.
  required final List<String> orderedKeys,
  required final Map<String, Color> colors,
  required final Map<String, int> totalLinesByKey,
  required final String Function(String relativeFilePath) resolveKey,
}) {
  Color colorForKey(String key) =>
      colors[key] ?? LineAgeDirectoryGroups.otherColor;

  Color colorForFile(String relativeFilePath) =>
      colorForKey(resolveKey(relativeFilePath));

  /// Directory → lines in [month], keys in [orderedKeys] order.
  List<({String key, int lineCount})> stacksForMonth(LineAgeMonth month) {
    final counts = <String, int>{for (final key in orderedKeys) key: 0};
    for (final segment in month.segments) {
      final key = resolveKey(segment.file);
      counts[key] = (counts[key] ?? 0) + segment.lineCount;
    }
    return [
      for (final key in orderedKeys)
        if ((counts[key] ?? 0) > 0) (key: key, lineCount: counts[key]!),
    ];
  }
}
