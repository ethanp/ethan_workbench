import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../ui/workbench_action_accents.dart';
import 'line_age_analyzer.dart';
import 'line_age_directory_groups.dart';

class const LineAgeMonthDirectoryGroup({
  required final String directory,
  required final Color color,
  required final List<LineAgeSegment> files,
});

/// Scrollable per-file breakdown for a selected month — used in the header popover.
class const LineAgeMonthFileList({
  required final LineAgeReport report,
  required final LineAgeDirectoryLegend legend,
  required final LineAgeMonth month,
  required final String? focusedFile,
  required final String? emphasizedDirectory,
  required final ValueChanged<String?> onFocusFile,
  required final ValueChanged<String?> onHoverDirectory,
  required final double maxHeight,
}) extends StatelessWidget {
  static const width = 440.0;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: EColors.surface.withValues(alpha: 0.98),
          borderRadius: ELayout.borderRadiusMd,
          border: Border.all(color: EColors.border.withValues(alpha: 0.8)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final group in _groupedSegments()) _directorySection(group),
            ],
          ),
        ),
      ),
    );
  }

  List<LineAgeMonthDirectoryGroup> _groupedSegments() {
    final buckets = <String, List<LineAgeSegment>>{};
    for (final segment in month.segments) {
      final key = legend.resolveKey(segment.file);
      buckets.putIfAbsent(key, () => []).add(segment);
    }
    return [
      for (final key in legend.orderedKeys)
        if (buckets.containsKey(key))
          LineAgeMonthDirectoryGroup(
            directory: key,
            color: legend.colorForKey(key),
            files: buckets[key]!,
          ),
    ];
  }

  Widget _directorySection(LineAgeMonthDirectoryGroup group) {
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
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
            padding: const EdgeInsets.fromLTRB(36, 4, 16, 6),
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
          padding: const EdgeInsets.fromLTRB(36, 7, 16, 7),
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
              const SizedBox(width: 16),
              Text(
                segment.lineCount.asCompactCount,
                softWrap: false,
                style: metricsStyle.copyWith(color: EColors.textMuted),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 44,
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
