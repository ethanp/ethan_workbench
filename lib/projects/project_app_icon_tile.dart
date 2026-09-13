import 'dart:typed_data';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

/// Rounded launcher icon for project / history list rows.
class const ProjectAppIconTile({
  super.key,
  final Uint8List? iconPngBytes,

  /// Defaults to [ELayout.iconTile]; list rows should pass [ELayout.listRowIcon].
  final double? size,
}) extends StatelessWidget {
  /// iOS app-icon corner radius ≈ 22.37% of the icon edge (not a fixed theme radius).
  static double iosCornerRadius(double edge) => edge * 0.2237;

  @override
  Widget build(BuildContext context) {
    final edge = size ?? ELayout.iconTile;
    final pixelEdge = (edge * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(iosCornerRadius(edge)),
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
                filterQuality: FilterQuality.low,
                cacheWidth: pixelEdge,
                cacheHeight: pixelEdge,
              ),
      ),
    );
  }
}
