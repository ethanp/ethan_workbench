import 'dart:async';

import 'package:flutter/material.dart';

import '../phone/deploy_http_client.dart';
import '../ui/theme/app_colors.dart';
import '../ui/theme/app_text.dart';
import '../ui/widgets/deploy_platform_controls.dart';
import '../ui/widgets/deploy_progress_checklist.dart';
import '../ui/widgets/log_console.dart';
import '../ui/widgets/status_pill.dart';
import 'deploy_job.dart';
import 'deploy_trigger.dart';

class JobScreen extends StatefulWidget {
  const JobScreen({
    super.key,
    required this.trigger,
    required this.initialJob,
  });

  final DeployTrigger trigger;
  final DeployJob initialJob;

  @override
  State<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends State<JobScreen> {
  late DeployJob _job;
  Timer? _pollTimer;
  String? _errorMessage;
  final _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _job = widget.initialJob;
    if (!_job.status.isTerminal) {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_refreshJob()),
      );
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshJob() async {
    try {
      final job = await widget.trigger.fetchJob(_job.jobId);
      if (!mounted) return;
      final shouldStickToBottom = !_logScrollController.hasClients ||
          _logScrollController.position.pixels >=
              _logScrollController.position.maxScrollExtent - 40;
      setState(() {
        _job = job;
        _errorMessage = null;
      });
      if (job.status.isTerminal) {
        _pollTimer?.cancel();
      }
      if (shouldStickToBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_logScrollController.hasClients) return;
          _logScrollController.jumpTo(
            _logScrollController.position.maxScrollExtent,
          );
        });
      }
    } on AgentRequestException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        _pollTimer?.cancel();
        final onUnauthorized = widget.trigger.onUnauthorized;
        if (onUnauthorized != null) {
          await onUnauthorized();
          if (mounted) Navigator.of(context).pop();
        }
        return;
      }
      setState(() => _errorMessage = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_job.projectName),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => unawaited(_refreshJob()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusHeader(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: AppText.body.copyWith(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 14),
            Text('BUILD LOG', style: AppText.label),
            const SizedBox(height: 8),
            Expanded(
              child: LogConsole(
                log: _job.log,
                controller: _logScrollController,
                emptyMessage: '(waiting for logs…)',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusHeader() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusSummaryRow(),
            if (_job.checklist.isNotEmpty) ...[
              const SizedBox(height: 14),
              DeployProgressChecklist(items: _job.checklist),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusSummaryRow() {
    return Row(
      children: [
        StatusPill.job(_job.status),
        const SizedBox(width: 10),
        DeployPlatformBadge(platform: _job.platform),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _job.force ? 'Force rebuild' : 'Incremental deploy',
                style: AppText.body,
              ),
              if (_job.exitCode != null)
                Text('Exit ${_job.exitCode}', style: AppText.caption),
            ],
          ),
        ),
      ],
    );
  }
}
