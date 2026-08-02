import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';

import '../deploy/deploy_job.dart';
import '../deploy/deploy_trigger.dart';
import '../phone/deploy_http_client.dart';

const _log = ELogger('ActiveDeployWatch');

/// Tracks the single non-terminal deploy for banner + per-project plates.
class ActiveDeployWatch {
  ActiveDeployWatch({
    required this.trigger,
    required this.onChanged,
  });

  final DeployTrigger trigger;
  final void Function() onChanged;

  DeployJob? ongoing;
  Timer? _poll;
  StreamSubscription<DeployJob>? _subscription;

  void start() {
    final jobUpdates = trigger.jobUpdates;
    if (jobUpdates != null) {
      _log.log('listening to jobUpdates + poll fallback');
      _subscription = jobUpdates.listen(_applyJobUpdate);
    } else {
      _log.log('no jobUpdates — polling fetchActiveJob every 2s');
    }
    // Always poll: phone SSE can stall even when a stream is wired.
    _poll ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  void _applyJobUpdate(DeployJob job) {
    final was = ongoing?.debugSummary ?? 'none';
    ongoing = job.status.isTerminal ? null : job;
    if (was != (ongoing?.debugSummary ?? 'none')) {
      _log.log(
        'stream update was=$was now=${ongoing?.debugSummary ?? 'none'}',
      );
    }
    onChanged();
  }

  void remember(DeployJob job) {
    ongoing = job.status.isTerminal ? null : job;
    _log.log('remember ${ongoing?.debugSummary ?? 'none'}');
    onChanged();
  }

  DeployJob? forProject(String projectId) {
    final job = ongoing;
    if (job == null || job.projectId != projectId) return null;
    return job;
  }

  Future<void> refresh() async {
    try {
      final job = await trigger.fetchActiveJob();
      final next = job != null && !job.status.isTerminal ? job : null;
      final was = ongoing?.debugSummary ?? 'none';
      final now = next?.debugSummary ?? 'none';
      ongoing = next;
      if (was != now) {
        _log.log('refresh $was → $now');
      }
      onChanged();
    } on AgentRequestException catch (error) {
      _log.warn('refresh failed: ${error.message}', error);
      if (error.isUnauthorized) {
        _poll?.cancel();
        await trigger.onUnauthorized?.call();
        return;
      }
      // Transient errors: keep the last known banner.
    } catch (error, stackTrace) {
      _log.warn('refresh failed', error, stackTrace);
      // Banner stays as-is until the next successful poll.
    }
  }

  Future<void> dispose() async {
    _poll?.cancel();
    await _subscription?.cancel();
  }
}
