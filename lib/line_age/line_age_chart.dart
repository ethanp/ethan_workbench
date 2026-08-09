import 'dart:math' as math;

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../ui/workbench_action_accents.dart';
import 'line_age_analyzer.dart';
import 'line_age_directory_groups.dart';

/// Month totals as bar height; directory identity as stable stack color.
class LineAgeChart extends StatefulWidget {
  const LineAgeChart({required this.report});

  final LineAgeReport report;

  @override
  State<LineAgeChart> createState() => _LineAgeChartState();
}

class _LineAgeChartState extends State<LineAgeChart> {
  LineAgeMonth? _hoveredMonth;
  LineAgeMonth? _selectedMonth;
  String? _focusedFile;
  String? _hoveredDirectory;

  late final LineAgeDirectoryLegend _legend =
      LineAgeDirectoryGroups.legendFor(widget.report);

  String? get _emphasizedDirectory {
    if (_hoveredDirectory != null) return _hoveredDirectory;
    if (_focusedFile != null) return _legend.resolveKey(_focusedFile!);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _histogram()),
              const SizedBox(height: ELayout.spaceSm),
              _DirectoryLegend(
                legend: _legend,
                emphasizedDirectory: _emphasizedDirectory,
                onHoverDirectory: (directory) =>
                    setState(() => _hoveredDirectory = directory),
              ),
            ],
          ),
        ),
        const SizedBox(width: ELayout.spaceMd),
        SizedBox(
          width: 380,
          child: _MonthDetailPanel(
            report: widget.report,
            legend: _legend,
            month: _selectedMonth,
            focusedFile: _focusedFile,
            emphasizedDirectory: _emphasizedDirectory,
            onFocusFile: (file) => setState(() {
              _focusedFile = file;
              if (file != null) _hoveredDirectory = null;
            }),
            onHoverDirectory: (directory) => setState(() {
              _hoveredDirectory = directory;
              if (directory != null) _focusedFile = null;
            }),
          ),
        ),
      ],
    );
  }

  Widget _histogram() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return MouseRegion(
          onExit: (_) => setState(() => _hoveredMonth = null),
          onHover: (event) {
            final month = _ChartGeometry(size).hitTestMonth(
              widget.report,
              event.localPosition,
            );
            if (month == _hoveredMonth) return;
            setState(() => _hoveredMonth = month);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final month = _ChartGeometry(size).hitTestMonth(
                widget.report,
                details.localPosition,
              );
              setState(() {
                _selectedMonth = month;
                _focusedFile = null;
              });
            },
            child: CustomPaint(
              painter: _LineAgeChartPainter(
                report: widget.report,
                legend: _legend,
                hoveredMonth: _hoveredMonth?.month,
                selectedMonth: _selectedMonth?.month,
                emphasizedDirectory: _emphasizedDirectory,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _DirectoryLegend extends StatelessWidget {
  const _DirectoryLegend({
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
              child: _legendChip(
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

  Widget _legendChip({
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

class _MonthDetailPanel extends StatelessWidget {
  const _MonthDetailPanel({
    required this.report,
    required this.legend,
    required this.month,
    required this.focusedFile,
    required this.emphasizedDirectory,
    required this.onFocusFile,
    required this.onHoverDirectory,
  });

  final LineAgeReport report;
  final LineAgeDirectoryLegend legend;
  final LineAgeMonth? month;
  final String? focusedFile;
  final String? emphasizedDirectory;
  final ValueChanged<String?> onFocusFile;
  final ValueChanged<String?> onHoverDirectory;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EColors.surface.withValues(alpha: 0.55),
        borderRadius: ELayout.borderRadiusMd,
        border: Border.all(color: EColors.border.withValues(alpha: 0.8)),
      ),
      child: month == null ? _emptyHint() : _monthBody(month!),
    );
  }

  Widget _emptyHint() {
    return Padding(
      padding: const EdgeInsets.all(ELayout.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Month detail', style: EText.section),
          const SizedBox(height: ELayout.spaceSm),
          Text(
            'Click a bar to inspect that month. '
            'Hover a directory (legend or list) to emphasize it '
            'across months.',
            style: EText.caption.copyWith(
              color: EColors.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthBody(LineAgeMonth month) {
    final groups = _groupedSegments(month);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(month.month, style: EText.section),
              const SizedBox(height: 4),
              Text(
                '${_formatCount(month.totalLines)} lines · '
                '${month.segments.length} files',
                style: EText.caption.copyWith(color: EColors.textMuted),
              ),
              const SizedBox(height: 8),
              Text(
                'Share of each file\'s current lines',
                style: EText.caption.copyWith(
                  color: EColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: EColors.border),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: groups.length,
            itemBuilder: (context, index) => _directorySection(groups[index]),
          ),
        ),
      ],
    );
  }

  List<({String directory, Color color, List<LineAgeSegment> files})>
      _groupedSegments(LineAgeMonth month) {
    final buckets = <String, List<LineAgeSegment>>{};
    for (final segment in month.segments) {
      final key = legend.resolveKey(segment.file);
      buckets.putIfAbsent(key, () => []).add(segment);
    }
    return [
      for (final key in legend.orderedKeys)
        if (buckets.containsKey(key))
          (
            directory: key,
            color: legend.colorForKey(key),
            files: buckets[key]!,
          ),
    ];
  }

  Widget _directorySection(
    ({String directory, Color color, List<LineAgeSegment> files}) group,
  ) {
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
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
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
            padding: const EdgeInsets.fromLTRB(28, 2, 12, 4),
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
          padding: const EdgeInsets.fromLTRB(28, 5, 12, 5),
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
              const SizedBox(width: 8),
              Text(
                _formatCount(segment.lineCount),
                softWrap: false,
                style: metricsStyle.copyWith(color: EColors.textMuted),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
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

  static String _formatCount(int value) {
    if (value >= 1000) {
      final thousands = value / 1000;
      return value % 1000 == 0
          ? '${thousands.toInt()}k'
          : '${thousands.toStringAsFixed(1)}k';
    }
    return '$value';
  }

  static String _basename(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? normalized : normalized.substring(slash + 1);
  }
}

class _ChartGeometry {
  _ChartGeometry(this.size)
    : margin = const EdgeInsets.fromLTRB(56, 36, 16, 56),
      innerWidth = math.max(0.0, size.width - 72),
      innerHeight = math.max(0.0, size.height - 92);

  final Size size;
  final EdgeInsets margin;
  final double innerWidth;
  final double innerHeight;

  static const maxBandWidth = 56.0;

  double bandWidth(int monthCount) {
    if (monthCount <= 0) return 0;
    return math.min(innerWidth / monthCount * 0.62, maxBandWidth);
  }

  double bandGap(int monthCount, double width) {
    if (monthCount <= 1) return 0;
    final leftover = innerWidth - width * monthCount;
    return math.max(leftover / monthCount, width * 0.35);
  }

  double groupOriginX(int monthCount, double width, double gap) {
    final groupWidth = monthCount * width + (monthCount - 1) * gap;
    return margin.left + math.max(0.0, (innerWidth - groupWidth) / 2);
  }

  double segmentHeight(num lineCount, double scaleMax) {
    if (scaleMax <= 0) return 0;
    return innerHeight * (lineCount / scaleMax);
  }

  double yForTotal(num totalLines, double scaleMax) =>
      margin.top + innerHeight - segmentHeight(totalLines, scaleMax);

  LineAgeMonth? hitTestMonth(LineAgeReport report, Offset position) {
    if (report.months.isEmpty) return null;
    final monthCount = report.months.length;
    final width = bandWidth(monthCount);
    final gap = bandGap(monthCount, width);
    final originX = groupOriginX(monthCount, width, gap);
    final plotBottom = margin.top + innerHeight;

    for (var monthIndex = 0; monthIndex < monthCount; monthIndex++) {
      final x = originX + monthIndex * (width + gap);
      if (position.dx < x || position.dx > x + width) continue;
      if (position.dy < margin.top || position.dy > plotBottom) continue;
      return report.months[monthIndex];
    }
    return null;
  }
}

class _LineAgeChartPainter extends CustomPainter {
  _LineAgeChartPainter({
    required this.report,
    required this.legend,
    required this.hoveredMonth,
    required this.selectedMonth,
    required this.emphasizedDirectory,
  });

  final LineAgeReport report;
  final LineAgeDirectoryLegend legend;
  final String? hoveredMonth;
  final String? selectedMonth;
  final String? emphasizedDirectory;

  @override
  void paint(Canvas canvas, Size size) {
    if (report.months.isEmpty) return;
    final geometry = _ChartGeometry(size);
    final dataMax = report.months
        .map((month) => month.totalLines)
        .reduce(math.max)
        .toDouble();
    final scale = NiceValueScale.forMax(dataMax);
    final monthCount = report.months.length;
    final width = geometry.bandWidth(monthCount);
    final gap = geometry.bandGap(monthCount, width);
    final originX = geometry.groupOriginX(monthCount, width, gap);

    _paintGrid(canvas, geometry, scale);
    _paintAxes(canvas, geometry, scale, width, gap, originX);
    _paintCaption(canvas, geometry);

    for (var monthIndex = 0; monthIndex < monthCount; monthIndex++) {
      final month = report.months[monthIndex];
      final x = originX + monthIndex * (width + gap);
      _paintMonthBar(
        canvas,
        geometry: geometry,
        month: month,
        x: x,
        width: width,
        scale: scale,
        isSelected: selectedMonth == month.month,
        isHovered: hoveredMonth == month.month,
      );
    }
  }

  void _paintMonthBar(
    Canvas canvas, {
    required _ChartGeometry geometry,
    required LineAgeMonth month,
    required double x,
    required double width,
    required NiceValueScale scale,
    required bool isSelected,
    required bool isHovered,
  }) {
    final stacks = legend.stacksForMonth(month);
    if (stacks.isEmpty) return;

    final barTop = geometry.yForTotal(month.totalLines, scale.max);
    final barHeight =
        geometry.margin.top + geometry.innerHeight - barTop;
    if (barHeight < 0.5) return;

    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, barTop, width, barHeight),
      const Radius.circular(4),
    );

    canvas.save();
    canvas.clipRRect(barRect);

    // Largest directories at the baseline.
    var yBottom = geometry.margin.top + geometry.innerHeight;
    for (final stack in stacks) {
      final height = geometry.segmentHeight(stack.lineCount, scale.max);
      if (height < 0.5) {
        yBottom -= height;
        continue;
      }
      final yTop = yBottom - height;
      final isEmphasized = emphasizedDirectory == null ||
          emphasizedDirectory == stack.key;
      final monthDim = !isSelected && !isHovered && selectedMonth != null;
      var alpha = isEmphasized ? 0.92 : 0.18;
      if (monthDim) alpha *= 0.55;
      if (isHovered && isEmphasized) alpha = math.min(1.0, alpha + 0.06);
      canvas.drawRect(
        Rect.fromLTWH(x, yTop, width, height),
        Paint()..color = legend.colorForKey(stack.key).withValues(alpha: alpha),
      );
      if (height > 2.5 && isEmphasized) {
        canvas.drawLine(
          Offset(x, yTop),
          Offset(x + width, yTop),
          Paint()
            ..color = EColors.surface.withValues(alpha: 0.45)
            ..strokeWidth = 1,
        );
      }
      yBottom = yTop;
    }

    canvas.restore();

    if (isSelected) {
      canvas.drawRRect(
        barRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = WorkbenchActionAccents.lineAge.withValues(alpha: 0.95),
      );
    }

    final emphasized = isSelected || isHovered;
    final valueLabel = TextPainter(
      text: TextSpan(
        text: _formatCount(month.totalLines),
        style: TextStyle(
          color: emphasized ? EColors.textPrimary : EColors.textMuted,
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    valueLabel.paint(
      canvas,
      Offset(x + width / 2 - valueLabel.width / 2, barTop - 16),
    );
  }

  void _paintGrid(
    Canvas canvas,
    _ChartGeometry geometry,
    NiceValueScale scale,
  ) {
    final paint = Paint()
      ..color = EColors.border.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (final tick in scale.ticks) {
      if (tick == 0) continue;
      final y = geometry.yForTotal(tick, scale.max);
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
    NiceValueScale scale,
    double width,
    double gap,
    double originX,
  ) {
    final baselineY = geometry.margin.top + geometry.innerHeight;
    final axisPaint = Paint()
      ..color = EColors.borderStrong.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(geometry.margin.left, baselineY),
      Offset(geometry.margin.left + geometry.innerWidth, baselineY),
      axisPaint,
    );

    for (final tick in scale.ticks) {
      final y = geometry.yForTotal(tick, scale.max);
      final label = TextPainter(
        text: TextSpan(
          text: _formatCount(tick.round()),
          style: const TextStyle(color: EColors.textMuted, fontSize: 11),
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
      final x = originX + monthIndex * (width + gap);
      final isSelected = selectedMonth == month;
      final isHovered = hoveredMonth == month;
      final label = TextPainter(
        text: TextSpan(
          text: month,
          style: TextStyle(
            color: isSelected || isHovered
                ? EColors.textPrimary
                : EColors.textMuted,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(x + width / 2, baselineY + 10);
      canvas.rotate(-0.65);
      label.paint(canvas, Offset(-label.width / 2, 0));
      canvas.restore();
    }
  }

  void _paintCaption(Canvas canvas, _ChartGeometry geometry) {
    final title = TextPainter(
      text: const TextSpan(
        text: 'Current lines by month · stacked by directory',
        style: TextStyle(
          color: EColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: geometry.innerWidth);
    title.paint(canvas, Offset(geometry.margin.left, 8));
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
      oldDelegate.report != report ||
      oldDelegate.legend != legend ||
      oldDelegate.hoveredMonth != hoveredMonth ||
      oldDelegate.selectedMonth != selectedMonth ||
      oldDelegate.emphasizedDirectory != emphasizedDirectory;
}
