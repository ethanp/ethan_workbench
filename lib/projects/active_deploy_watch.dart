import 'dart:async';

import '../deploy/deploy_job.dart';
import '../deploy/deploy_trigger.dart';
import '../phone/deploy_http_client.dart';

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
      _subscription = jobUpdates.listen(_applyJobUpdate);
    } else {
      _poll = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(refresh()),
      );
    }
    unawaited(refresh());
  }

  void _applyJobUpdate(DeployJob job) {
    ongoing = job.status.isTerminal ? null : job;
    onChanged();
  }

  void remember(DeployJob job) {
    ongoing = job.status.isTerminal ? null : job;
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
      ongoing = job != null && !job.status.isTerminal ? job : null;
      onChanged();
    } on AgentRequestException catch (error) {
      if (error.isUnauthorized) {
        _poll?.cancel();
        await trigger.onUnauthorized?.call();
        return;
      }
      // Transient errors: keep the last known banner.
    } catch (_) {
      // Banner stays as-is until the next successful poll.
    }
  }

  Future<void> dispose() async {
    _poll?.cancel();
    await _subscription?.cancel();
  }
}
