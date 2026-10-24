import 'dart:async';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../phone/deploy_http_client.dart';
import '../ui/workbench_domain_appearance.dart';
import '../ui/widgets/deploy_platform_controls.dart';
import '../ui/widgets/deploy_progress_checklist.dart';
import '../ui/widgets/status_pill.dart';
import 'deploy.dart';
import 'deploy_errors.dart';
import 'deploy_job.dart';
import 'deploy_trigger.dart';

const _log = ELogger('DeployJobDetail');

/// Live job status + build log. Full-screen ([JobScreen]) or Mac side rail.
class const DeployJobDetail({
  super.key,
  required final DeployTrigger trigger,
  required final DeployJob initialJob,

  /// Shown in the side-rail header; omitted in full-screen (AppBar back).
  final VoidCallback? onDismiss,

  /// Fired once when the job first reaches a terminal status.
  final VoidCallback? onBecameTerminal,

  /// Fired when Retry starts an active deploy (not a wait-queue enqueue).
  final void Function(DeployJob job)? onRetryStarted,

  /// Side-rail job detail (no scaffold).
  final bool inSideRail = false,
}) extends StatefulWidget {
  @override
  State<DeployJobDetail> createState() => _DeployJobDetailState();
}

class _DeployJobDetailState() extends State<DeployJobDetail> {
  late DeployJob _job;
  Timer? _pollTimer;
  StreamSubscription<DeployJob>? _jobUpdatesSubscription;
  String? _errorMessage;
  final _logScrollController = ScrollController();
  var _streamEventCount = 0;
  var _reportedTerminal = false;
  var _retrying = false;
  var _retryingInstall = false;
  var _refreshInFlight = false;

  @override
  void initState() {
    super.initState();
    _job = widget.initialJob;
    _reportedTerminal = _job.status.isTerminal;
    _log.log(
      'open initial=${_job.debugSummary} '
      'inSideRail=${widget.inSideRail} '
      'jobUpdates=${widget.trigger.jobUpdates != null}',
    );
    if (_job.status.isTerminal) return;

    final jobUpdates = widget.trigger.jobUpdates;
    if (jobUpdates != null) {
      _jobUpdatesSubscription = jobUpdates.listen(_showStreamedJobIfThisJob);
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
  void didUpdateWidget(covariant DeployJobDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialJob.jobId == widget.initialJob.jobId) return;
    unawaited(_watchThisJob(widget.initialJob));
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

  void _showStreamedJobIfThisJob(DeployJob job) {
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
    if (statusChanged ||
        _streamEventCount == 1 ||
        _streamEventCount % 25 == 0) {
      _log.log(
        'apply stream #$_streamEventCount ${job.debugSummary}'
        '${logGrew ? ' (log delta)' : ''}',
      );
    }
    _showJobAndStickLogToBottom(job);
    if (job.status.isTerminal) {
      unawaited(_jobUpdatesSubscription?.cancel());
      _jobUpdatesSubscription = null;
    }
  }

  Future<void> _refreshJob() async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final job = await widget.trigger.fetchJob(_job.jobId);
      if (!mounted) return;
      if (job.status != _job.status || job.log.length != _job.log.length) {
        _log.log('poll refresh ${job.debugSummary}');
      }
      _showJobAndStickLogToBottom(job);
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
          if (mounted && !widget.inSideRail) {
            Navigator.of(context).pop();
          }
        }
        return;
      }
      setState(() => _errorMessage = error.message);
    } on TimeoutException catch (error, stackTrace) {
      if (!mounted) return;
      _log.warn('status poll timed out', error, stackTrace);
    } catch (error, stackTrace) {
      if (!mounted) return;
      _log.warn('poll refresh failed', error, stackTrace);
      setState(() => _errorMessage = error.toString());
    } finally {
      _refreshInFlight = false;
    }
  }

  void _showJobAndStickLogToBottom(DeployJob job) {
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

  Future<void> _retryDeploy(Deploy deploy) async {
    if (_retrying || !_job.status.isFailed) return;
    setState(() {
      _retrying = true;
      _retryingInstall = deploy.installStep.existingBuild;
    });
    _log.log(
      'retry ${_job.projectId} ${_job.platform.name} '
      'force=${deploy.force} ${deploy.installStep.existingBuild ? deploy.install.logDetail : 'full'}',
    );
    try {
      final job = await widget.trigger.startDeploy(
        projectId: _job.projectId,
        deploy: deploy,
      );
      if (!mounted) return;
      if (job.status.isWaiting) {
        setState(() => _retrying = false);
        context.textSnackBar(
          'Queued ${_job.projectName} (${_job.platform.label})',
        );
        return;
      }
      final onRetryStarted = widget.onRetryStarted;
      if (onRetryStarted != null) {
        setState(() => _retrying = false);
        onRetryStarted(job);
        return;
      }
      await _watchThisJob(job);
    } on DeployAlreadyQueued catch (error) {
      if (!mounted) return;
      setState(() => _retrying = false);
      context.textSnackBar(error.toString());
    } on ServerRequestException catch (error) {
      if (!mounted) return;
      setState(() => _retrying = false);
      if (error.isUnauthorized) {
        await widget.trigger.onUnauthorized?.call();
        return;
      }
      context.textSnackBar(error.message);
    } catch (error, stackTrace) {
      if (!mounted) return;
      _log.warn('retry failed', error, stackTrace);
      setState(() => _retrying = false);
      context.textSnackBar(error.toString());
    }
  }

  Future<void> _watchThisJob(DeployJob job) async {
    _pollTimer?.cancel();
    await _jobUpdatesSubscription?.cancel();
    _jobUpdatesSubscription = null;
    _streamEventCount = 0;
    _reportedTerminal = job.status.isTerminal;
    setState(() {
      _job = job;
      _errorMessage = null;
      _retrying = false;
    });
    if (job.status.isTerminal) return;

    final jobUpdates = widget.trigger.jobUpdates;
    if (jobUpdates != null) {
      _jobUpdatesSubscription = jobUpdates.listen(_showStreamedJobIfThisJob);
    }
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshJob()),
    );
    unawaited(_refreshJob());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inSideRail) return _sideRailBody();
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

  Widget _sideRailBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sideRailHeader(),
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

  Widget _sideRailHeader() {
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
              style: EText.label.medium.copyWith(color: EColors.textPrimary),
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
              constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
              child: SingleChildScrollView(child: _statusHeader()),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: EText.body.medium.copyWith(color: EColors.danger),
              ),
            ],
            const SizedBox(height: 14),
            Text('BUILD LOG', style: EText.label.small),
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
          if (_job.status.isFailed) ...[
            const SizedBox(height: ELayout.spaceMd + 2),
            _retryActions(),
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
              Text(_job.modeLabel, style: EText.body.medium),
              if (_job.exitCode != null)
                Text('Exit ${_job.exitCode}', style: EText.caption),
            ],
          ),
        ),
      ],
    );
  }

  Widget _retryActions() {
    final retry = _job.installStep?.install.retry(force: _job.force);
    final full = Deploy.full(platform: _job.platform, force: _job.force);
    if (retry == null) {
      return _retryButton(
        icon: Icons.replay_rounded,
        title: 'Retry',
        subtitle: '${_job.platform.label} deploy',
        deploy: full,
      );
    }
    return Column(
      children: [
        _retryButton(
          icon: Icons.replay_rounded,
          title: 'Retry',
          subtitle: retry.installStep.label,
          deploy: retry,
        ),
        const SizedBox(height: ELayout.spaceSm),
        _retryButton(
          icon: Icons.refresh_rounded,
          title: 'Full retry',
          subtitle: _job.force ? 'Force rebuild' : 'Rebuild and install',
          deploy: full,
        ),
      ],
    );
  }

  Widget _retryButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Deploy deploy,
  }) {
    final platform = _job.platform;
    final thisButtonBusy =
        _retrying && _retryingInstall == deploy.installStep.existingBuild;
    final accent = _retrying ? EColors.textMuted : platform.accent;
    return ETintedAction.compact(
      accent: accent,
      icon: icon,
      title: title,
      subtitle: subtitle,
      onActivated: _retrying ? null : () => unawaited(_retryDeploy(deploy)),
      trailing: thisButtonBusy
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            )
          : null,
    );
  }
}

/// Full-screen job route (phone / compact).
class const JobScreen({
  required final DeployTrigger trigger,
  required final DeployJob initialJob,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DeployJobDetail(trigger: trigger, initialJob: initialJob);
  }
}
