import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../ui/workbench_action_accents.dart';
import 'line_age_analyzer.dart';
import 'line_age_directory_groups.dart';

/// File breakdown for the selected month, grouped by directory.
class LineAgeMonthDetailPanel extends StatelessWidget {
  const LineAgeMonthDetailPanel({
    required this.report,
    required this.legend,
    required this.month,
    required this.focusedFile,
    required this.emphasizedDirectory,
    required this.onFocusFile,
    required this.onHoverDirectory,
  });

  final LineAgeReport report;
  final LineAgeDirectoryLegend legend;
  final LineAgeMonth? month;
  final String? focusedFile;
  final String? emphasizedDirectory;
  final ValueChanged<String?> onFocusFile;
  final ValueChanged<String?> onHoverDirectory;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EColors.surface.withValues(alpha: 0.55),
        borderRadius: ELayout.borderRadiusMd,
        border: Border.all(color: EColors.border.withValues(alpha: 0.8)),
      ),
      child: month == null ? _emptyHint() : _monthBody(month!),
    );
  }

  Widget _emptyHint() {
    return Padding(
      padding: const EdgeInsets.all(ELayout.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Month detail', style: EText.section),
          const SizedBox(height: ELayout.spaceSm),
          Text(
            'Click a stack segment to select that month and directory. '
            'Hover a directory (legend or list) to preview emphasis.',
            style: EText.caption.copyWith(
              color: EColors.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthBody(LineAgeMonth month) {
    final groups = _groupedSegments(month);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(month.month, style: EText.section),
              const SizedBox(height: 4),
              Text(
                '${month.totalLines.asCompactCount} lines · '
                '${month.segments.length} files',
                style: EText.caption.copyWith(color: EColors.textMuted),
              ),
              const SizedBox(height: 8),
              Text(
                'Share of each file\'s current lines',
                style: EText.caption.copyWith(
                  color: EColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: EColors.border),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: groups.length,
            itemBuilder: (context, index) => _directorySection(groups[index]),
          ),
        ),
      ],
    );
  }

  List<({String directory, Color color, List<LineAgeSegment> files})>
      _groupedSegments(LineAgeMonth month) {
    final buckets = <String, List<LineAgeSegment>>{};
    for (final segment in month.segments) {
      final key = legend.resolveKey(segment.file);
      buckets.putIfAbsent(key, () => []).add(segment);
    }
    return [
      for (final key in legend.orderedKeys)
        if (buckets.containsKey(key))
          (
            directory: key,
            color: legend.colorForKey(key),
            files: buckets[key]!,
          ),
    ];
  }

  Widget _directorySection(
    ({String directory, Color color, List<LineAgeSegment> files}) group,
  ) {
    final isEmphasized = emphasizedDirectory == group.directory;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          onEnter: (_) => onHoverDirectory(group.directory),
          onExit: (_) => onHoverDirectory(null),
          child: ColoredBox(
            color: isEmphasized
                ? group.color.withValues(alpha: 0.14)
                : Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: group.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      group.directory,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: EText.caption.copyWith(
                        color: isEmphasized
                            ? EColors.textPrimary
                            : EColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        for (final segment in group.files.take(8)) _fileRow(segment),
        if (group.files.length > 8)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 2, 12, 4),
            child: Text(
              '+ ${group.files.length - 8} more',
              style: EText.caption.copyWith(color: EColors.textMuted),
            ),
          ),
      ],
    );
  }

  Widget _fileRow(LineAgeSegment segment) {
    final fileTotal = report.totalLinesByFile[segment.file] ?? 0;
    final pctOfFile = fileTotal == 0
        ? 0.0
        : segment.lineCount / fileTotal * 100;
    final isFocused = focusedFile == segment.file;
    final metricsStyle = EText.mono.copyWith(
      fontSize: 12,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return MouseRegion(
      onEnter: (_) => onFocusFile(segment.file),
      onExit: (_) {
        if (focusedFile == segment.file) onFocusFile(null);
      },
      child: ColoredBox(
        color: isFocused
            ? WorkbenchActionAccents.lineAge.withValues(alpha: 0.12)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 5, 12, 5),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _basename(segment.file),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: EText.caption.copyWith(
                    color: isFocused
                        ? EColors.textPrimary
                        : EColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                segment.lineCount.asCompactCount,
                softWrap: false,
                style: metricsStyle.copyWith(color: EColors.textMuted),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(
                  '${pctOfFile.toStringAsFixed(0)}%',
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.right,
                  style: metricsStyle.copyWith(
                    color: isFocused
                        ? legend.colorForFile(segment.file)
                        : EColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _basename(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? normalized : normalized.substring(slash + 1);
  }
}
