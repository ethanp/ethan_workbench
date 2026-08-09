import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import 'line_age_analyzer.dart';
import 'line_age_directory_groups.dart';
import 'line_age_directory_legend_bar.dart';
import 'line_age_histogram_geometry.dart';
import 'line_age_histogram_painter.dart';
import 'line_age_month_detail_panel.dart';

/// Line-age overview: histogram + directory legend + month detail panel.
///
/// Owns selection/hover focus and composes the deep chart collaborators.
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
  String? _selectedDirectory;

  late final LineAgeDirectoryLegend _legend =
      LineAgeDirectoryGroups.legendFor(widget.report);

  String? get _emphasizedDirectory {
    if (_hoveredDirectory != null) return _hoveredDirectory;
    if (_focusedFile != null) return _legend.resolveKey(_focusedFile!);
    return _selectedDirectory;
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
              LineAgeDirectoryLegendBar(
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
          child: LineAgeMonthDetailPanel(
            report: widget.report,
            legend: _legend,
            month: _selectedMonth,
            focusedFile: _focusedFile,
            emphasizedDirectory: _emphasizedDirectory,
            onFocusFile: (file) => setState(() {
              _focusedFile = file;
              if (file != null) {
                _hoveredDirectory = null;
                _selectedDirectory = _legend.resolveKey(file);
              }
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
        final geometry = LineAgeHistogramGeometry(size);
        return MouseRegion(
          onExit: (_) => setState(() {
            _hoveredMonth = null;
            _hoveredDirectory = null;
          }),
          onHover: (event) {
            final hit = geometry.hitTestStack(
              report: widget.report,
              legend: _legend,
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
                legend: _legend,
                position: details.localPosition,
              );
              setState(() {
                _selectedMonth = hit?.month;
                _selectedDirectory = hit?.directory;
                _focusedFile = null;
                _hoveredDirectory = null;
              });
            },
            child: CustomPaint(
              painter: LineAgeHistogramPainter(
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
