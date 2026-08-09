import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../ui/workbench_action_accents.dart';
import 'line_age_analyzer.dart';

/// Blame loading UI — spinner until the first tick, then a 12px capsule track.
class LineAgeBlameProgress extends StatelessWidget {
  const LineAgeBlameProgress({this.progress});

  final LineAgeProgress? progress;

  static const _trackHeight = 12.0;
  static const _pathLineHeight = 1.3;
  static const _minWidth = 420.0;
  static const _maxWidth = 640.0;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    if (progress == null) return const _LineAgeBlameStarting();

    final accent = WorkbenchActionAccents.lineAge;
    final percent = (progress.fraction * 100).clamp(0, 100).round();
    final relativePath = progress.currentRelativePath;
    final fileName = relativePath.isEmpty
        ? 'Preparing…'
        : p.basename(relativePath);
    final directory = relativePath.isEmpty
        ? ''
        : p.dirname(relativePath).replaceAll(r'\', '/');
    final showDirectory = directory.isNotEmpty && directory != '.';

    final availableWidth = MediaQuery.sizeOf(context).width - 64;
    final width = availableWidth.clamp(_minWidth, _maxWidth);
    final directoryStyle = EText.caption.copyWith(
      color: EColors.textMuted,
      height: _pathLineHeight,
    );
    final fileNameStyle = EText.body.copyWith(
      color: EColors.textSecondary,
      height: _pathLineHeight,
    );

    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pathLine(
            showDirectory ? directory : ' ',
            style: directoryStyle,
          ),
          _pathLine(fileName, style: fileNameStyle),
          const SizedBox(height: 18),
          _capsuleTrack(accent: accent, fraction: progress.fraction),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '$percent%',
                style: EText.label.copyWith(
                  color: accent,
                  letterSpacing: 0.6,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Text(
                '${progress.completedFiles} / ${progress.totalFiles} files',
                style: EText.caption.copyWith(
                  color: EColors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Fixed strut height so path swaps never change column size or overflow.
  Widget _pathLine(String text, {required TextStyle style}) {
    final fontSize = style.fontSize ?? 14;
    return SizedBox(
      height: fontSize * _pathLineHeight,
      child: Text(
        text,
        style: style,
        textAlign: TextAlign.left,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        strutStyle: StrutStyle(
          fontSize: fontSize,
          height: _pathLineHeight,
          forceStrutHeight: true,
        ),
      ),
    );
  }

  Widget _capsuleTrack({
    required Color accent,
    required double fraction,
  }) {
    final radius = BorderRadius.circular(_trackHeight);
    return SizedBox(
      height: _trackHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: EColors.surfaceInset,
          borderRadius: radius,
          border: Border.all(color: EColors.border.withValues(alpha: 0.75)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.18),
              blurRadius: 16,
              spreadRadius: 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      accent.withValues(alpha: 0.78),
                      accent,
                      Color.lerp(accent, Colors.white, 0.22)!,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LineAgeBlameStarting extends StatelessWidget {
  const _LineAgeBlameStarting();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: WorkbenchActionAccents.lineAge.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Starting git blame…',
          style: EText.caption.copyWith(color: EColors.textMuted),
        ),
      ],
    );
  }
}
