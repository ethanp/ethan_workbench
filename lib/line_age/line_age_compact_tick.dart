import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/painting.dart';

/// Left-axis compact count label (`2.5k`).
class LineAgeCompactTick._(final TextPainter _painter) {
  factory of(num value) {
    return LineAgeCompactTick._(
      TextPainter(
        text: TextSpan(
          text: value.round().asCompactCount,
          style: const TextStyle(color: EColors.textMuted, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  double get width => _painter.width;

  double get height => _painter.height;

  void paint(Canvas canvas, Offset offset) => _painter.paint(canvas, offset);
}
