import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import 'line_age_analyzer.dart';
import 'line_age_directory_groups.dart';
import 'line_age_directory_legend_bar.dart';
import 'line_age_histogram_geometry.dart';
import 'line_age_histogram_painter.dart';

/// Line-age histogram + directory legend. Selection lives on [LineAgeScreen].
class LineAgeChart extends StatefulWidget {
  const LineAgeChart({
    required this.report,
    required this.legend,
    required this.selectedMonth,
    required this.selectedDirectory,
    required this.emphasizedDirectory,
    required this.onStackSelected,
  });

  final LineAgeReport report;
  final LineAgeDirectoryLegend legend;
  final LineAgeMonth? selectedMonth;
  final String? selectedDirectory;
  final String? emphasizedDirectory;
  final void Function(LineAgeMonth? month, String? directory) onStackSelected;

  @override
  State<LineAgeChart> createState() => _LineAgeChartState();
}

class _LineAgeChartState extends State<LineAgeChart> {
  LineAgeMonth? _hoveredMonth;
  String? _hoveredDirectory;

  String? get _emphasizedDirectory {
    if (_hoveredDirectory != null) return _hoveredDirectory;
    return widget.emphasizedDirectory;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _histogram()),
        const SizedBox(height: ELayout.spaceSm),
        LineAgeDirectoryLegendBar(
          legend: widget.legend,
          emphasizedDirectory: _emphasizedDirectory,
          onHoverDirectory: (directory) =>
              setState(() => _hoveredDirectory = directory),
        ),
      ],
    );
  }

  Widget _histogram() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final geometry = LineAgeHistogramGeometry(size);
        return MouseRegion(
          onExit: (_) => setState(() {
            _hoveredMonth = null;
            _hoveredDirectory = null;
          }),
          onHover: (event) {
            final hit = geometry.hitTestStack(
              report: widget.report,
              legend: widget.legend,
              position: event.localPosition,
            );
            if (hit?.month == _hoveredMonth &&
                hit?.directory == _hoveredDirectory) {
              return;
            }
            setState(() {
              _hoveredMonth = hit?.month;
              _hoveredDirectory = hit?.directory;
            });
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final hit = geometry.hitTestStack(
                report: widget.report,
                legend: widget.legend,
                position: details.localPosition,
              );
              widget.onStackSelected(hit?.month, hit?.directory);
            },
            child: CustomPaint(
              painter: LineAgeHistogramPainter(
                report: widget.report,
                legend: widget.legend,
                hoveredMonth: _hoveredMonth?.month,
                selectedMonth: widget.selectedMonth?.month,
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
