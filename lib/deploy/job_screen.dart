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

const _log = ELogger('DeployJobDetail');

/// Live job status + build log. Full-screen ([JobScreen]) or Mac side rail.
class DeployJobDetail extends StatefulWidget {
  const DeployJobDetail({
    super.key,
    required this.trigger,
    required this.initialJob,
    this.onDismiss,
    this.onBecameTerminal,
    this.embedded = false,
  });

  final DeployTrigger trigger;
  final DeployJob initialJob;

  /// Shown in the embedded header; omitted in full-screen (AppBar back).
  final VoidCallback? onDismiss;

  /// Fired once when the job first reaches a terminal status.
  final VoidCallback? onBecameTerminal;

  /// Compact chrome for the side rail (no scaffold).
  final bool embedded;

  @override
  State<DeployJobDetail> createState() => _DeployJobDetailState();
}

class _DeployJobDetailState extends State<DeployJobDetail> {
  late DeployJob _job;
  Timer? _pollTimer;
  StreamSubscription<DeployJob>? _jobUpdatesSubscription;
  String? _errorMessage;
  final _logScrollController = ScrollController();
  var _streamEventCount = 0;
  var _reportedTerminal = false;

  @override
  void initState() {
    super.initState();
    _job = widget.initialJob;
    _reportedTerminal = _job.status.isTerminal;
    _log.log(
      'open initial=${_job.debugSummary} '
      'embedded=${widget.embedded} '
      'jobUpdates=${widget.trigger.jobUpdates != null}',
    );
    if (_job.status.isTerminal) return;

    final jobUpdates = widget.trigger.jobUpdates;
    if (jobUpdates != null) {
      _jobUpdatesSubscription = jobUpdates.listen(_applyStreamedJob);
      _log.log('subscribed to jobUpdates + poll fallback');
    } else {
      _log.log('no jobUpdates stream — polling fetchJob every 2s');
    }

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

  void _applyStreamedJob(DeployJob job) {
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
    } on ServerRequestException catch (error) {
      if (!mounted) return;
      _log.warn('poll refresh failed: ${error.message}', error);
      if (error.isUnauthorized) {
        _pollTimer?.cancel();
        unawaited(_jobUpdatesSubscription?.cancel());
        final onUnauthorized = widget.trigger.onUnauthorized;
        if (onUnauthorized != null) {
          await onUnauthorized();
          if (mounted && !widget.embedded) {
            Navigator.of(context).pop();
          }
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
    if (job.status.isTerminal && !_reportedTerminal) {
      _reportedTerminal = true;
      widget.onBecameTerminal?.call();
    }
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
    if (widget.embedded) return _embeddedBody();
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
        child: _detailColumn(),
      ),
    );
  }

  Widget _embeddedBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _embeddedHeader(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ELayout.spaceMd,
              0,
              ELayout.spaceMd,
              ELayout.spaceMd,
            ),
            child: _detailColumn(),
          ),
        ),
      ],
    );
  }

  Widget _embeddedHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ELayout.spaceMd,
        ELayout.spaceSm,
        ELayout.spaceXs,
        ELayout.spaceSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _job.projectName,
              style: EText.label.copyWith(color: EColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => unawaited(_refreshJob()),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: EColors.textMuted,
          ),
          if (widget.onDismiss != null)
            IconButton(
              tooltip: 'Close',
              onPressed: widget.onDismiss,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
              color: EColors.textMuted,
            ),
        ],
      ),
    );
  }

  Widget _detailColumn() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The checklist grows a row per deploy step; in short viewports
            // let the status panel scroll within half the height instead of
            // overflowing and starving the log console.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight / 2,
              ),
              child: SingleChildScrollView(child: _statusHeader()),
            ),
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
        );
      },
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

/// Full-screen job route (phone / compact).
class JobScreen extends StatelessWidget {
  const JobScreen({required this.trigger, required this.initialJob});

  final DeployTrigger trigger;
  final DeployJob initialJob;

  @override
  Widget build(BuildContext context) {
    return DeployJobDetail(
      trigger: trigger,
      initialJob: initialJob,
    );
  }
}
