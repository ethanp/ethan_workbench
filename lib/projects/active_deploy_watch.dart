import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';

import '../deploy/deploy_duration_estimate.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_trigger.dart';
import '../phone/deploy_http_client.dart';

const _log = ELogger('ActiveDeployWatch');

/// Tracks the active deploy and FIFO wait queue for banner + queue panel.
class ActiveDeployWatch {
  ActiveDeployWatch({
    required this.trigger,
    required this.onChanged,
  });

  final DeployTrigger trigger;
  final void Function() onChanged;

  DeployJob? ongoing;
  List<DeployJob> waiting = const [];

  /// Median successful duration for [ongoing]'s project/platform, when known.
  Duration? ongoingTypicalDuration;

  Timer? _poll;
  StreamSubscription<DeployJob>? _jobSubscription;
  StreamSubscription<List<DeployJob>>? _queueSubscription;
  String? _typicalDurationCacheKey;

  bool get hasQueuePanelContent =>
      ongoing != null || waiting.isNotEmpty;

  /// Remaining wall time vs typical successful runs; null if no baseline yet.
  Duration? get ongoingRemainingEstimate {
    final job = ongoing;
    final typical = ongoingTypicalDuration;
    if (job == null || typical == null) return null;
    return DeployDurationEstimate.remaining(
      typical: typical,
      startedAt: job.createdAt,
    );
  }

  void start() {
    final jobUpdates = trigger.jobUpdates;
    if (jobUpdates != null) {
      _log.log('listening to jobUpdates + poll fallback');
      _jobSubscription = jobUpdates.listen(_applyJobUpdate);
    } else {
      _log.log('no jobUpdates — polling fetchActiveJob every 2s');
    }
    final queueUpdates = trigger.queueUpdates;
    if (queueUpdates != null) {
      _queueSubscription = queueUpdates.listen(_applyQueueUpdate);
    }
    // Always poll: phone SSE can stall even when a stream is wired.
    _poll ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  void _applyJobUpdate(DeployJob job) {
    if (job.status.isWaiting) return;
    final was = ongoing?.debugSummary ?? 'none';
    ongoing = job.status.isTerminal ? null : job;
    if (ongoing == null) {
      ongoingTypicalDuration = null;
      _typicalDurationCacheKey = null;
    } else {
      unawaited(_ensureTypicalDuration(ongoing!));
    }
    if (was != (ongoing?.debugSummary ?? 'none')) {
      _log.log(
        'stream update was=$was now=${ongoing?.debugSummary ?? 'none'}',
      );
    }
    onChanged();
  }

  void _applyQueueUpdate(List<DeployJob> jobs) {
    waiting = List.unmodifiable(jobs);
    onChanged();
  }

  void remember(DeployJob job) {
    if (job.status.isWaiting) return;
    ongoing = job.status.isTerminal ? null : job;
    if (ongoing == null) {
      ongoingTypicalDuration = null;
      _typicalDurationCacheKey = null;
    } else {
      unawaited(_ensureTypicalDuration(ongoing!));
    }
    _log.log('remember ${ongoing?.debugSummary ?? 'none'}');
    onChanged();
  }

  DeployJob? forProject(String projectId) {
    final job = ongoing;
    if (job == null || job.projectId != projectId) return null;
    return job;
  }

  DeployJob? waitingFor({
    required String projectId,
    required String platformName,
  }) {
    for (final job in waiting) {
      if (job.projectId == projectId && job.platform.name == platformName) {
        return job;
      }
    }
    return null;
  }

  Future<void> refresh() async {
    try {
      final job = await trigger.fetchActiveJob();
      final next = job != null && !job.status.isTerminal ? job : null;
      final queue = await trigger.fetchDeployQueue();
      final was = ongoing?.debugSummary ?? 'none';
      final now = next?.debugSummary ?? 'none';
      ongoing = next;
      waiting = List.unmodifiable(queue);
      if (next == null) {
        ongoingTypicalDuration = null;
        _typicalDurationCacheKey = null;
      } else {
        await _ensureTypicalDuration(next);
      }
      if (was != now) {
        _log.log('refresh $was → $now waiting=${waiting.length}');
      }
      onChanged();
    } on AgentRequestException catch (error) {
      _log.warn('refresh failed: ${error.message}', error);
      if (error.isUnauthorized) {
        _poll?.cancel();
        await trigger.onUnauthorized?.call();
        return;
      }
      // Transient errors: keep the last known banner / queue.
    } catch (error, stackTrace) {
      _log.warn('refresh failed', error, stackTrace);
    }
  }

  Future<void> _ensureTypicalDuration(DeployJob job) async {
    final cacheKey = '${job.projectId}:${job.platform.name}:${job.force}';
    if (cacheKey == _typicalDurationCacheKey) return;
    try {
      final runs = await trigger.listDeployHistory();
      ongoingTypicalDuration = DeployDurationEstimate.medianSuccessful(
        runs: runs,
        projectId: job.projectId,
        platform: job.platform,
        force: job.force,
      );
      _typicalDurationCacheKey = cacheKey;
    } catch (error, stackTrace) {
      _log.warn('typical duration lookup failed', error, stackTrace);
    }
  }

  Future<void> cancelWaiting(String jobId) async {
    await trigger.cancelQueuedDeploy(jobId);
    await refresh();
  }

  Future<void> dispose() async {
    _poll?.cancel();
    await _jobSubscription?.cancel();
    await _queueSubscription?.cancel();
  }
}
