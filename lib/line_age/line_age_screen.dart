import 'dart:async';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import 'line_age_analyzer.dart';
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

  @override
  Widget build(BuildContext context) {
    return EScaffoldShell(
      appBar: AppBar(
        title: Text('Line age — ${widget.repoName}', style: EText.title),
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              '${report.totalLines} lines across ${report.fileCount} files',
              style: EText.caption,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LineAgeChart(report: report),
            ),
          ),
        ],
      );
    }

    final progress = _progress;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              _running ? 'Analyzing with git blame…' : 'Starting…',
              style: EText.section,
            ),
            if (progress != null) ...[
              const SizedBox(height: 10),
              Text(
                '${progress.completedFiles}/${progress.totalFiles}'
                '${progress.currentRelativePath.isEmpty ? '' : ' — ${progress.currentRelativePath}'}',
                style: EText.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: 280,
                child: LinearProgressIndicator(value: progress.fraction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
