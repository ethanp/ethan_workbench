import 'dart:async';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../phone/deploy_http_client.dart';
import '../ui/widgets/deploy_platform_controls.dart';
import '../ui/widgets/deploy_progress_checklist.dart';
import '../ui/widgets/status_pill.dart';
import 'deploy_job.dart';
import 'deploy_trigger.dart';

const _log = ELogger('JobScreen');

class JobScreen extends StatefulWidget {
  const JobScreen({required this.trigger, required this.initialJob});

  final DeployTrigger trigger;
  final DeployJob initialJob;

  @override
  State<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends State<JobScreen> {
  late DeployJob _job;
  Timer? _pollTimer;
  StreamSubscription<DeployJob>? _jobUpdatesSubscription;
  String? _errorMessage;
  final _logScrollController = ScrollController();
  var _streamEventCount = 0;

  @override
  void initState() {
    super.initState();
    _job = widget.initialJob;
    _log.log(
      'open initial=${_job.debugSummary} '
      'jobUpdates=${widget.trigger.jobUpdates != null}',
    );
    if (_job.status.isTerminal) return;

    final jobUpdates = widget.trigger.jobUpdates;
    if (jobUpdates != null) {
      _jobUpdatesSubscription = jobUpdates.listen(_onJobUpdate);
      _log.log('subscribed to jobUpdates + poll fallback');
    } else {
      _log.log('no jobUpdates stream — polling fetchJob every 2s');
    }

    // Always poll: phone SSE can stall even when a stream is wired.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshJob()),
    );
    unawaited(_refreshJob());
  }

  @override
  void dispose() {
    _log.log(
      'dispose jobId=${_job.jobId} status=${_job.status.name} '
      'streamEvents=$_streamEventCount',
    );
    _pollTimer?.cancel();
    unawaited(_jobUpdatesSubscription?.cancel());
    _logScrollController.dispose();
    super.dispose();
  }

  void _onJobUpdate(DeployJob job) {
    if (!mounted) return;
    _streamEventCount += 1;
    if (job.jobId != _job.jobId) {
      _log.warn(
        'ignored stream event #$_streamEventCount '
        'wanted=${_job.jobId} got=${job.debugSummary}',
      );
      return;
    }
    final statusChanged = job.status != _job.status;
    final logGrew = job.log.length != _job.log.length;
    if (statusChanged || _streamEventCount == 1 || _streamEventCount % 25 == 0) {
      _log.log(
        'apply stream #$_streamEventCount ${job.debugSummary}'
        '${logGrew ? ' (log delta)' : ''}',
      );
    }
    _applyJob(job);
    if (job.status.isTerminal) {
      unawaited(_jobUpdatesSubscription?.cancel());
      _jobUpdatesSubscription = null;
    }
  }

  Future<void> _refreshJob() async {
    try {
      final job = await widget.trigger.fetchJob(_job.jobId);
      if (!mounted) return;
      if (job.status != _job.status || job.log.length != _job.log.length) {
        _log.log('poll refresh ${job.debugSummary}');
      }
      _applyJob(job);
      if (job.status.isTerminal) {
        _pollTimer?.cancel();
      }
    } on AgentRequestException catch (error) {
      if (!mounted) return;
      _log.warn('poll refresh failed: ${error.message}', error);
      if (error.isUnauthorized) {
        _pollTimer?.cancel();
        unawaited(_jobUpdatesSubscription?.cancel());
        final onUnauthorized = widget.trigger.onUnauthorized;
        if (onUnauthorized != null) {
          await onUnauthorized();
          if (mounted) Navigator.of(context).pop();
        }
        return;
      }
      setState(() => _errorMessage = error.message);
    } catch (error, stackTrace) {
      if (!mounted) return;
      _log.warn('poll refresh failed', error, stackTrace);
      setState(() => _errorMessage = error.toString());
    }
  }

  void _applyJob(DeployJob job) {
    final shouldStickToBottom =
        !_logScrollController.hasClients ||
        _logScrollController.position.pixels >=
            _logScrollController.position.maxScrollExtent - 40;
    setState(() {
      _job = job;
      _errorMessage = null;
    });
    if (!shouldStickToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScrollController.hasClients) return;
      final position = _logScrollController.position;
      if (!position.hasContentDimensions) return;
      _logScrollController.jumpTo(position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return EScaffoldShell(
      appBar: AppBar(
        title: Text(_job.projectName, style: EText.title),
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
                style: EText.body.copyWith(color: EColors.danger),
              ),
            ],
            const SizedBox(height: 14),
            Text('BUILD LOG', style: EText.label),
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
    return ESurface(
      kind: ESurfaceKind.panel,
      padding: const EdgeInsets.all(ELayout.spaceMd + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusSummaryRow(),
          if (_job.checklist.isNotEmpty) ...[
            const SizedBox(height: ELayout.spaceMd + 2),
            DeployProgressChecklist(items: _job.checklist),
          ],
        ],
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
                style: EText.body,
              ),
              if (_job.exitCode != null)
                Text('Exit ${_job.exitCode}', style: EText.caption),
            ],
          ),
        ),
      ],
    );
  }
}
