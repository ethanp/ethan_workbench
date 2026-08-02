import 'dart:typed_data';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

/// Rounded launcher icon for project / history list rows.
class ProjectAppIconTile extends StatelessWidget {
  const ProjectAppIconTile({
    super.key,
    this.iconPngBytes,
    this.size,
  });

  final Uint8List? iconPngBytes;

  /// Defaults to [ELayout.iconTile]; list rows should pass [ELayout.listRowIcon].
  final double? size;

  /// iOS app-icon corner radius ≈ 22.37% of the icon edge (not a fixed theme radius).
  static double iosCornerRadius(double edge) => edge * 0.2237;

  @override
  Widget build(BuildContext context) {
    final edge = size ?? ELayout.iconTile;
    final radius = BorderRadius.circular(iosCornerRadius(edge));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: edge,
          height: edge,
          child: iconPngBytes == null
              ? ColoredBox(
                  color: EColors.surfaceInset,
                  child: Icon(
                    Icons.apps_rounded,
                    size: edge * 0.42,
                    color: EColors.textMuted,
                  ),
                )
              : Image.memory(
                  iconPngBytes!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
        ),
      ),
    );
  }
}
