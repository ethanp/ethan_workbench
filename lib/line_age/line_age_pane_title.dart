import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/painting.dart';

/// Shared pane heading for project size and last-touched.
class LineAgePaneTitle(final String text) {
  static const style = TextStyle(
    color: EColors.textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  void paint(Canvas canvas, Offset offset, {required double maxWidth}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }
}
