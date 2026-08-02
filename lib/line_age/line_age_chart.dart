import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import 'line_age_analyzer.dart';

const _palette = <Color>[
  Color(0xFF4e79a7),
  Color(0xFFf28e2b),
  Color(0xFFe15759),
  Color(0xFF76b7b2),
  Color(0xFF59a14f),
  Color(0xFFedc948),
  Color(0xFFb07aa1),
  Color(0xFFff9da7),
  Color(0xFF9c755f),
  Color(0xFFbab0ac),
  Color(0xFF17becf),
  Color(0xFFaec7e8),
  Color(0xFFffbb78),
  Color(0xFF98df8a),
  Color(0xFFff9896),
  Color(0xFFc5b0d5),
  Color(0xFFc49c94),
  Color(0xFFf7b6d2),
  Color(0xFFdbdb8d),
  Color(0xFF9edae5),
  Color(0xFF393b79),
  Color(0xFF637939),
  Color(0xFF8c6d31),
  Color(0xFF843c39),
  Color(0xFF7b4173),
  Color(0xFF5254a3),
  Color(0xFF8ca252),
  Color(0xFFbd9e39),
  Color(0xFFad494a),
  Color(0xFFa55194),
];

class LineAgeChart extends StatefulWidget {
  const LineAgeChart({required this.report});

  final LineAgeReport report;

  @override
  State<LineAgeChart> createState() => _LineAgeChartState();
}

class _LineAgeChartState extends State<LineAgeChart> {
  _HoverTip? _tip;

  Map<String, Color> get _fileColors {
    final colors = <String, Color>{};
    for (var index = 0;
        index < widget.report.filesByTotalLines.length;
        index++) {
      colors[widget.report.filesByTotalLines[index]] =
          _palette[index % _palette.length];
    }
    return colors;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return MouseRegion(
          onExit: (_) => setState(() => _tip = null),
          onHover: (event) => _updateTip(event.localPosition, size),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _LineAgeChartPainter(
                    report: widget.report,
                    fileColors: _fileColors,
                  ),
                ),
              ),
              if (_tip != null) _tooltip(size),
            ],
          ),
        );
      },
    );
  }

  void _updateTip(Offset localPosition, Size size) {
    final tip = _ChartGeometry(size).hitTest(widget.report, localPosition);
    setState(() => _tip = tip);
  }

  Widget _tooltip(Size size) {
    final tip = _tip!;
    const tipWidth = 320.0;
    final left = tip.anchor.dx + 14 + tipWidth > size.width
        ? tip.anchor.dx - tipWidth - 14
        : tip.anchor.dx + 14;
    final top = (tip.anchor.dy - 36).clamp(8.0, size.height - 72);
    final pct = tip.month.totalLines == 0
        ? '0.0'
        : (tip.segment.lineCount / tip.month.totalLines * 100)
            .toStringAsFixed(1);
    return Positioned(
      left: left.clamp(8.0, size.width - tipWidth - 8),
      top: top,
      width: tipWidth,
      child: IgnorePointer(
        child: Material(
          color: EColors.surfaceRaised.withValues(alpha: 0.94),
          borderRadius: ELayout.borderRadiusMd,
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              '${tip.segment.file}\n'
              '${tip.month.month}: ${tip.segment.lineCount} lines '
              '($pct% of month)',
              style: EText.caption.copyWith(color: EColors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverTip {
  const _HoverTip({
    required this.month,
    required this.segment,
    required this.anchor,
  });

  final LineAgeMonth month;
  final LineAgeSegment segment;
  final Offset anchor;
}

class _ChartGeometry {
  _ChartGeometry(this.size)
    : margin = const EdgeInsets.fromLTRB(64, 28, 24, 72),
      innerWidth = math.max(0.0, size.width - 88),
      innerHeight = math.max(0.0, size.height - 100);

  final Size size;
  final EdgeInsets margin;
  final double innerWidth;
  final double innerHeight;

  double bandWidth(int monthCount) {
    if (monthCount <= 0) return 0;
    return (innerWidth / monthCount) * 0.82;
  }

  double bandGap(int monthCount) {
    if (monthCount <= 0) return 0;
    return (innerWidth / monthCount) * 0.18;
  }

  double segmentHeight(int lineCount, int maxTotal) {
    if (maxTotal <= 0) return 0;
    return innerHeight * (lineCount / (maxTotal * 1.04));
  }

  double yForTotal(int totalLines, int maxTotal) =>
      margin.top + innerHeight - segmentHeight(totalLines, maxTotal);

  _HoverTip? hitTest(LineAgeReport report, Offset position) {
    if (report.months.isEmpty) return null;
    final maxTotal = report.months
        .map((month) => month.totalLines)
        .reduce(math.max);
    final monthCount = report.months.length;
    final width = bandWidth(monthCount);
    final gap = bandGap(monthCount);

    for (var monthIndex = 0; monthIndex < monthCount; monthIndex++) {
      final month = report.months[monthIndex];
      final x = margin.left + monthIndex * (width + gap) + gap / 2;
      if (position.dx < x || position.dx > x + width) continue;

      // Segments are largest-first; paint/hit stack with largest at bottom.
      var yBottom = margin.top + innerHeight;
      for (final segment in month.segments.reversed) {
        final height = segmentHeight(segment.lineCount, maxTotal);
        final yTop = yBottom - height;
        if (height >= 0.5 &&
            position.dy >= yTop &&
            position.dy <= yBottom) {
          return _HoverTip(
            month: month,
            segment: segment,
            anchor: position,
          );
        }
        yBottom = yTop;
      }
    }
    return null;
  }
}

class _LineAgeChartPainter extends CustomPainter {
  _LineAgeChartPainter({required this.report, required this.fileColors});

  final LineAgeReport report;
  final Map<String, Color> fileColors;

  @override
  void paint(Canvas canvas, Size size) {
    if (report.months.isEmpty) return;
    final geometry = _ChartGeometry(size);
    final maxTotal = report.months
        .map((month) => month.totalLines)
        .reduce(math.max);
    final monthCount = report.months.length;
    final width = geometry.bandWidth(monthCount);
    final gap = geometry.bandGap(monthCount);

    _paintGrid(canvas, geometry, maxTotal);
    _paintAxes(canvas, geometry, maxTotal, width, gap);
    _paintTitle(canvas, geometry);

    for (var monthIndex = 0; monthIndex < monthCount; monthIndex++) {
      final month = report.months[monthIndex];
      final x = geometry.margin.left + monthIndex * (width + gap) + gap / 2;
      var yBottom = geometry.margin.top + geometry.innerHeight;
      for (final segment in month.segments.reversed) {
        final height = geometry.segmentHeight(segment.lineCount, maxTotal);
        if (height < 0.5) {
          yBottom -= height;
          continue;
        }
        final yTop = yBottom - height;
        canvas.drawRect(
          Rect.fromLTWH(x, yTop, width, height),
          Paint()..color = fileColors[segment.file] ?? const Color(0xFFaaaaaa),
        );
        yBottom = yTop;
      }

      final barTop = geometry.yForTotal(month.totalLines, maxTotal);
      final label = TextPainter(
        text: TextSpan(
          text: 'files: ${month.segments.length}',
          style: const TextStyle(
            color: Color(0xFF444444),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(x + width / 2 - label.width / 2, barTop - 16),
      );
    }
  }

  void _paintGrid(Canvas canvas, _ChartGeometry geometry, int maxTotal) {
    final paint = Paint()
      ..color = const Color(0xFFF2F2F2)
      ..strokeWidth = 1;
    for (var tick = 0; tick <= 8; tick++) {
      final value = (maxTotal * 1.04 * tick / 8).round();
      final y = geometry.yForTotal(value, maxTotal);
      canvas.drawLine(
        Offset(geometry.margin.left, y),
        Offset(geometry.margin.left + geometry.innerWidth, y),
        paint,
      );
    }
  }

  void _paintAxes(
    Canvas canvas,
    _ChartGeometry geometry,
    int maxTotal,
    double width,
    double gap,
  ) {
    final axisPaint = Paint()
      ..color = const Color(0xFFDDDDDD)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(geometry.margin.left, geometry.margin.top),
      Offset(
        geometry.margin.left,
        geometry.margin.top + geometry.innerHeight,
      ),
      axisPaint,
    );
    canvas.drawLine(
      Offset(
        geometry.margin.left,
        geometry.margin.top + geometry.innerHeight,
      ),
      Offset(
        geometry.margin.left + geometry.innerWidth,
        geometry.margin.top + geometry.innerHeight,
      ),
      axisPaint,
    );

    for (var tick = 0; tick <= 8; tick++) {
      final value = (maxTotal * 1.04 * tick / 8).round();
      final y = geometry.yForTotal(value, maxTotal);
      final label = TextPainter(
        text: TextSpan(
          text: _formatCount(value),
          style: const TextStyle(color: Color(0xFF666666), fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(geometry.margin.left - label.width - 8, y - label.height / 2),
      );
    }

    for (var monthIndex = 0; monthIndex < report.months.length; monthIndex++) {
      final month = report.months[monthIndex].month;
      final x = geometry.margin.left + monthIndex * (width + gap) + gap / 2;
      final label = TextPainter(
        text: TextSpan(
          text: month,
          style: const TextStyle(color: Color(0xFF666666), fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(
        x + width / 2,
        geometry.margin.top + geometry.innerHeight + 10,
      );
      canvas.rotate(-0.7);
      label.paint(canvas, Offset(-label.width / 2, 0));
      canvas.restore();
    }

    final yTitle = TextPainter(
      text: const TextSpan(
        text: 'Lines',
        style: TextStyle(color: Color(0xFF666666), fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(18, geometry.margin.top + geometry.innerHeight / 2);
    canvas.rotate(-math.pi / 2);
    yTitle.paint(canvas, Offset(-yTitle.width / 2, 0));
    canvas.restore();
  }

  void _paintTitle(Canvas canvas, _ChartGeometry geometry) {
    final title = TextPainter(
      text: TextSpan(
        text: 'Lines by Last Modified Month — ${report.repoName}',
        style: const TextStyle(
          color: Color(0xFF333333),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: geometry.innerWidth);
    title.paint(
      canvas,
      Offset(
        geometry.margin.left + geometry.innerWidth / 2 - title.width / 2,
        6,
      ),
    );
  }

  String _formatCount(int value) {
    if (value >= 1000) {
      final thousands = value / 1000;
      return value % 1000 == 0
          ? '${thousands.toInt()}k'
          : '${thousands.toStringAsFixed(1)}k';
    }
    return '$value';
  }

  @override
  bool shouldRepaint(covariant _LineAgeChartPainter oldDelegate) =>
      oldDelegate.report != report || oldDelegate.fileColors != fileColors;
}
