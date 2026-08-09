import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import 'line_age_directory_groups.dart';

/// Color key for directory stacks — hover previews emphasis on the histogram.
class LineAgeDirectoryLegendBar extends StatelessWidget {
  const LineAgeDirectoryLegendBar({
    required this.legend,
    required this.emphasizedDirectory,
    required this.onHoverDirectory,
  });

  final LineAgeDirectoryLegend legend;
  final String? emphasizedDirectory;
  final ValueChanged<String?> onHoverDirectory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 56, right: 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          for (final key in legend.orderedKeys)
            MouseRegion(
              onEnter: (_) => onHoverDirectory(key),
              onExit: (_) => onHoverDirectory(null),
              child: _chip(
                key: key,
                color: legend.colorForKey(key),
                emphasized: emphasizedDirectory == null ||
                    emphasizedDirectory == key,
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String key,
    required Color color,
    required bool emphasized,
  }) {
    return Opacity(
      opacity: emphasized ? 1 : 0.35,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            key,
            style: EText.caption.copyWith(
              color: EColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
