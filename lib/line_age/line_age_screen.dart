import 'dart:async';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../ui/workbench_action_accents.dart';
import 'line_age_analyzer.dart';
import 'line_age_blame_progress.dart';
import 'line_age_chart.dart';

class LineAgeScreen extends StatefulWidget {
  const LineAgeScreen({
    required this.repoPath,
    required this.repoName,
  });

  final String repoPath;
  final String repoName;

  @override
  State<LineAgeScreen> createState() => _LineAgeScreenState();
}

class _LineAgeScreenState extends State<LineAgeScreen> {
  late final LineAgeAnalyzer _analyzer;
  LineAgeProgress? _progress;
  LineAgeReport? _report;
  String? _errorMessage;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _analyzer = LineAgeAnalyzer(repoPath: widget.repoPath);
    unawaited(_run());
  }

  @override
  void dispose() {
    _analyzer.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _errorMessage = null;
      _report = null;
    });
    try {
      final report = await _analyzer.analyze(
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _running = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _running = false;
      });
    }
  }

  String? get _headerSubtitle {
    final report = _report;
    if (report != null) {
      return '${report.totalLines.asCompactCount} Dart lines · '
          '${report.fileCount} files · last-touched months';
    }
    if (_errorMessage != null) return 'Analysis failed';
    if (_running) {
      final progress = _progress;
      if (progress == null) return 'Starting git blame…';
      return 'Blaming ${progress.completedFiles}/${progress.totalFiles} files';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return EScaffoldShell(
      contentMaxWidth: ELayout.contentMaxWidth * 2,
      appBar: EAppHeader(
        eyebrow: 'LINE AGE',
        title: widget.repoName,
        subtitle: _headerSubtitle,
        accent: WorkbenchActionAccents.lineAge,
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, style: EText.body, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => unawaited(_run()),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final report = _report;
    if (report != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: LineAgeChart(report: report),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: LineAgeBlameProgress(progress: _progress),
      ),
    );
  }
}
