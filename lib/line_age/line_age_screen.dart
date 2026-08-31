import 'dart:async';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../ui/workbench_action_accents.dart';
import 'line_age_analyzer.dart';
import 'line_age_report.dart';
import 'line_age_blame_progress.dart';
import 'line_age_cache.dart';
import 'line_age_chart.dart';
import 'line_age_directory_groups.dart';
import 'line_age_month_detail_header.dart';

class const LineAgeScreen({
  required final String repoPath,
  required final String repoName,
}) extends StatefulWidget {
  @override
  State<LineAgeScreen> createState() => _LineAgeScreenState();
}

class _LineAgeScreenState() extends State<LineAgeScreen> {
  late final LineAgeAnalyzer _analyzer;
  LineAgeProgress? _progress;
  LineAgeReport? _report;
  String? _errorMessage;
  bool _running = true;

  LineAgeMonth? _selectedMonth;
  String? _selectedDirectory;
  String? _focusedFile;
  String? _hoveredDirectory;

  @override
  void initState() {
    super.initState();
    _analyzer = LineAgeAnalyzer(repoPath: widget.repoPath);
    unawaited(_analyzeOrShowCached());
  }

  @override
  void dispose() {
    _analyzer.cancel();
    super.dispose();
  }

  Future<void> _analyzeOrShowCached() async {
    setState(() {
      _running = true;
      _errorMessage = null;
      _progress = null;
    });
    try {
      await LineAgeCache.instance.ensureLoaded();
      final gitRoot = LineAgeCache.gitRootFor(widget.repoPath);
      final stored = gitRoot == null
          ? null
          : LineAgeCache.instance.lastStoredReport(gitRoot);
      if (stored != null && mounted) {
        setState(() => _report = stored);
      }
      if (stored != null &&
          gitRoot != null &&
          LineAgeCache.instance.isFingerprintCurrent(gitRoot)) {
        if (!mounted) return;
        setState(() => _running = false);
        return;
      }

      final report = await _analyzer.analyze(
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (gitRoot != null) {
        LineAgeCache.instance.put(
          gitRoot: gitRoot,
          fingerprint: LineAgeCache.computeFingerprint(gitRoot),
          report: report,
        );
      }
      if (!mounted) return;
      setState(() {
        _keepSelectedMonthIfStillPresent(report);
        _running = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (_report == null) _errorMessage = error.toString();
        _running = false;
      });
    }
  }

  void _keepSelectedMonthIfStillPresent(LineAgeReport report) {
    final selectedKey = _selectedMonth?.month;
    LineAgeMonth? nextMonth;
    if (selectedKey != null) {
      for (final month in report.months) {
        if (month.month == selectedKey) {
          nextMonth = month;
          break;
        }
      }
    }
    _report = report;
    _selectedMonth = nextMonth;
    if (nextMonth == null) {
      _selectedDirectory = null;
      _focusedFile = null;
      _hoveredDirectory = null;
    }
  }

  void _selectMonthAndDirectory(LineAgeMonth? month, String? directory) {
    setState(() {
      _selectedMonth = month;
      _selectedDirectory = directory;
      _focusedFile = null;
      _hoveredDirectory = null;
    });
  }

  String? _emphasizedFromPopover(LineAgeDirectoryLegend legend) {
    if (_hoveredDirectory != null) return _hoveredDirectory;
    if (_focusedFile != null) return legend.resolveKey(_focusedFile!);
    return _selectedDirectory;
  }

  String? get _headerSubtitle {
    final report = _report;
    if (report != null) {
      final projectSizeToday = report.projectSizeByMonth.at(
        DateTime.now().yearMonthKey,
      );
      final projectSizeCaption = projectSizeToday == null
          ? ''
          : ' · ${projectSizeToday.asCompactCount} project size';
      return '${report.totalLines.asCompactCount} last-touched · '
          '${report.fileCount} files$projectSizeCaption';
    }
    if (_errorMessage != null) return 'Analysis failed';
    if (_running) {
      final progress = _progress;
      if (progress == null) return 'Measuring last-touched months…';
      return 'Last-touched ${progress.completedFiles}/'
          '${progress.totalFiles} files';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final legend = report == null
        ? null
        : LineAgeDirectoryGroups.legendFor(report);
    return EScaffoldShell(
      contentMaxWidth: double.infinity,
      appBar: EAppHeader(
        eyebrow: 'LINE AGE',
        title: widget.repoName,
        subtitle: _headerSubtitle,
        accent: WorkbenchActionAccents.lineAge,
        actions: [
          if (report != null && legend != null)
            LineAgeMonthDetailHeaderAction(
              report: report,
              legend: legend,
              month: _selectedMonth,
              focusedFile: _focusedFile,
              emphasizedDirectory: _emphasizedFromPopover(legend),
              onFocusFile: (file) => setState(() {
                _focusedFile = file;
                if (file != null) {
                  _hoveredDirectory = null;
                  _selectedDirectory = legend.resolveKey(file);
                }
              }),
              onHoverDirectory: (directory) => setState(() {
                _hoveredDirectory = directory;
                if (directory != null) _focusedFile = null;
              }),
              onDismissed: () => _selectMonthAndDirectory(null, null),
            ),
        ],
      ),
      body: _body(report: report, legend: legend),
    );
  }

  Widget _body({
    required LineAgeReport? report,
    required LineAgeDirectoryLegend? legend,
  }) {
    if (_errorMessage != null) return _failedAnalysis();
    if (report != null && legend != null) {
      return _chartWithRefresh(report, legend);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: LineAgeBlameProgress(progress: _progress),
      ),
    );
  }

  Widget _failedAnalysis() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _errorMessage!,
              style: EText.body.medium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => unawaited(_analyzeOrShowCached()),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartWithRefresh(
    LineAgeReport report,
    LineAgeDirectoryLegend legend,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_running) LineAgeRefreshBar(progress: _progress),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: LineAgeChart(
              report: report,
              legend: legend,
              selectedMonth: _selectedMonth,
              selectedDirectory: _selectedDirectory,
              emphasizedDirectory: _emphasizedFromPopover(legend),
              onMonthAndDirectorySelected: _selectMonthAndDirectory,
            ),
          ),
        ),
      ],
    );
  }
}
