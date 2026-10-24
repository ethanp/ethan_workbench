import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import 'line_age_directory_groups.dart';

/// Color key for directory stacks — hover previews emphasis on the histogram.
class const LineAgeDirectoryLegendBar({
  required final LineAgeDirectoryLegend legend,
  required final String? emphasizedDirectory,
  required final ValueChanged<String?> onHoverDirectory,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 56, right: 8),
      child: EChartLegend(
        entries: [
          for (final key in legend.orderedKeys)
            _directoryEntry(key),
        ],
      ),
    );
  }

  EChartLegendEntry _directoryEntry(String key) {
    final dimmed = emphasizedDirectory != null && emphasizedDirectory != key;
    final color = legend.colorForKey(key);
    return EChartLegendEntry(
      swatch: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: dimmed ? color.withValues(alpha: 0.35) : color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      label: key,
      labelStyle: EText.caption.copyWith(color: EColors.textSecondary),
      dimmed: dimmed,
      onHoverChanged: (hovering) => onHoverDirectory(hovering ? key : null),
    );
  }
}
