import 'dart:typed_data';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

/// Rounded launcher icon for project / history list rows.
class ProjectAppIconTile extends StatelessWidget {
  const ProjectAppIconTile({super.key, this.iconPngBytes});

  final Uint8List? iconPngBytes;

  @override
  Widget build(BuildContext context) {
    final radius = ELayout.borderRadiusLg;
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
          width: ELayout.iconTile,
          height: ELayout.iconTile,
          child: iconPngBytes == null
              ? const ColoredBox(
                  color: EColors.surfaceInset,
                  child: Icon(
                    Icons.apps_rounded,
                    size: 34,
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
