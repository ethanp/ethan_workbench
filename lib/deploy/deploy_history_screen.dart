import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../app_identity.dart';
import 'deploy_job.dart';
import 'deploy_run_record.dart';
import 'deploy_trigger.dart';
import 'job_screen.dart';
import '../phone/deploy_http_client.dart';
import '../projects/project_app_icon_tile.dart';

/// Activity list of past (and in-progress) deploys from the ledger / server.
class DeployHistoryScreen extends StatefulWidget {
  const DeployHistoryScreen({super.key, required this.trigger});

  final DeployTrigger trigger;

  @override
  State<DeployHistoryScreen> createState() => _DeployHistoryScreenState();
}

class _DeployHistoryScreenState extends State<DeployHistoryScreen> {
  static const _jobDetailRailWidth = 440.0;

  List<DeployRunRecord> _runs = const [];
  Map<String, Uint8List> _iconsByProjectId = const {};
  bool _loading = true;
  String? _errorMessage;
  StreamSubscription<DeployJob>? _jobUpdatesSubscription;
  Timer? _historyPoll;

  /// Run opened in the right rail (null = rail closed). Compact pushes
  /// the full-screen [JobScreen] instead.
  DeployJob? _selectedRunJob;

  @override
  void initState() {
    super.initState();
    final jobUpdates = widget.trigger.jobUpdates;
    if (jobUpdates != null) {
      _jobUpdatesSubscription = jobUpdates.listen((_) {
        unawaited(_loadHistory(showSpinner: false));
      });
    }
    // Always poll: first paint often races ledger attach / PowerSync download.
    _historyPoll = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_loadHistory(showSpinner: false)),
    );
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    _historyPoll?.cancel();
    unawaited(_jobUpdatesSubscription?.cancel());
    super.dispose();
  }

  Future<void> _loadHistory({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    try {
      final runs = await widget.trigger.listDeployHistory();
      final iconsByProjectId = showSpinner || _iconsByProjectId.isEmpty
          ? await _loadIconsByProjectId()
          : _iconsByProjectId;
      if (!mounted) return;
      setState(() {
        _runs = runs;
        _iconsByProjectId = iconsByProjectId;
        _loading = false;
        _errorMessage = null;
      });
    } on ServerRequestException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        _historyPoll?.cancel();
        await widget.trigger.onUnauthorized?.call();
        return;
      }
      setState(() {
        _loading = false;
        if (_runs.isEmpty) _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_runs.isEmpty) _errorMessage = error.toString();
      });
    }
  }

  Future<Map<String, Uint8List>> _loadIconsByProjectId() async {
    try {
      final projects = await widget.trigger.listProjects();
      return {
        for (final project in projects)
          if (project.iconPngBytes != null)
            project.projectId: project.iconPngBytes!,
      };
    } catch (_) {
      return _iconsByProjectId;
    }
  }

  Future<void> _showRunDeployPanel(DeployRunRecord run) async {
    try {
      final job = await widget.trigger.fetchJob(run.runId);
      if (!mounted) return;
      if (MediaQuery.sizeOf(context).shortestSide < 600) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => JobScreen(
              trigger: widget.trigger,
              initialJob: job,
            ),
          ),
        );
        return;
      }
      setState(() => _selectedRunJob = job);
    } on ServerRequestException catch (error) {
      if (!mounted) return;
      context.textSnackBar('Could not load deploy: ${error.message}');
    } catch (error) {
      if (!mounted) return;
      context.textSnackBar('Could not load deploy: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedRunJob = _selectedRunJob;
    final showJobRail = selectedRunJob != null &&
        MediaQuery.sizeOf(context).shortestSide >= 600;
    return EScaffoldShell(
      contentMaxWidth:
          showJobRail ? double.infinity : ELayout.feedContentMaxWidth,
      appBar: EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: 'History',
      ),
      body: showJobRail
          ? _bodyWithJobRail(selectedRunJob)
          : _body(),
    );
  }

  /// History list + deploy detail rail; surplus width past feed comfort
  /// goes to the rail.
  Widget _bodyWithJobRail(DeployJob selectedRunJob) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final railWidth = math.max(
          _jobDetailRailWidth,
          constraints.maxWidth - ELayout.feedContentMaxWidth,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _body()),
            ESidePanel(
              title: 'Deploy',
              width: railWidth,
              child: DeployJobDetail(
                key: ValueKey(selectedRunJob.jobId),
                trigger: widget.trigger,
                initialJob: selectedRunJob,
                embedded: true,
                onDismiss: () => setState(() => _selectedRunJob = null),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _body() {
    if (_loading && _runs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _runs.isEmpty) {
      return _emptyMessage(
        title: 'Could not load history',
        detail: _errorMessage!,
        actionLabel: 'Retry',
        onAction: () => unawaited(_loadHistory()),
      );
    }
    if (_runs.isEmpty) {
      return _emptyMessage(
        title: 'No deploys yet',
        detail:
            'Past deploys appear here after they sync. Pull to refresh if you '
            'just opened the app.',
      );
    }

    return RefreshIndicator(
      color: EColors.accentGlow,
      backgroundColor: EColors.surface,
      onRefresh: _loadHistory,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          ELayout.spaceXl,
          ELayout.spaceMd,
          ELayout.spaceXl,
          ELayout.spaceXl + 8,
        ),
        itemCount: _runs.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: ELayout.spaceMd + 2),
        itemBuilder: (context, index) => _runRow(_runs[index]),
      ),
    );
  }

  Widget _runRow(DeployRunRecord run) {
    return ESurface(
      kind: ESurfaceKind.row,
      attention: run.runId == _selectedRunJob?.jobId,
      onActivated: () => unawaited(_showRunDeployPanel(run)),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          ProjectAppIconTile(
            iconPngBytes: _iconsByProjectId[run.projectId],
          ),
          const SizedBox(width: ELayout.spaceLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  run.projectName,
                  style: EText.projectName,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      run.platform.icon,
                      color: run.platform.accent,
                      size: 14,
                    ),
                    const SizedBox(width: ELayout.spaceSm),
                    Flexible(
                      child: Text(
                        _runSubtitle(run),
                        style: EText.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: ELayout.spaceMd),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              EStatusChip(
                label: run.status.pillLabel,
                tone: run.status.statusTone,
              ),
              const SizedBox(height: 6),
              Text(
                run.elapsed.formattedElapsed,
                style: EText.caption,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _runSubtitle(DeployRunRecord run) {
    final when = run.startedAt.relativeTimeAgo();
    final where = run.platform.label;
    final force = run.force ? ' · force' : '';
    return '$where · $when$force';
  }

  Widget _emptyMessage({
    required String title,
    required String detail,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.history_rounded,
              size: 48,
              color: EColors.textMuted,
            ),
            const SizedBox(height: 18),
            Text(title, style: EText.section, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(detail, style: EText.body, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }
}
