import 'dart:async';

import 'deploy_job.dart';
import 'deploy_platform.dart';

/// FIFO of deploys waiting behind the active runner.
class DeployWaitQueue {
  DeployWaitQueue({this.onQueueChanged});

  final void Function()? onQueueChanged;
  final List<DeployJob> _jobs = [];
  final _updates = StreamController<List<DeployJob>>.broadcast();

  List<DeployJob> get jobs => List.unmodifiable(_jobs);
  Stream<List<DeployJob>> get updates => _updates.stream;
  bool get isEmpty => _jobs.isEmpty;
  bool get isNotEmpty => _jobs.isNotEmpty;

  void enqueue(DeployJob job) {
    _jobs.add(job);
    _emit();
  }

  /// Removes a waiting job. Returns false if [jobId] is not queued.
  bool cancel(String jobId) {
    final index = _jobs.indexWhere((job) => job.jobId == jobId);
    if (index < 0) return false;
    _jobs.removeAt(index);
    _emit();
    return true;
  }

  DeployJob? takeNext() {
    if (_jobs.isEmpty) return null;
    final next = _jobs.removeAt(0);
    _emit();
    return next;
  }

  void replaceAll(Iterable<DeployJob> jobs) {
    _jobs
      ..clear()
      ..addAll(jobs);
    _emit();
  }

  DeployJob? findSameTarget({
    required String projectId,
    required DeployPlatform platform,
  }) {
    for (final job in _jobs) {
      if (job.projectId == projectId && job.platform == platform) return job;
    }
    return null;
  }

  DeployJob? jobById(String jobId) {
    for (final job in _jobs) {
      if (job.jobId == jobId) return job;
    }
    return null;
  }

  Future<void> dispose() => _updates.close();

  void _emit() {
    if (!_updates.isClosed) {
      _updates.add(List.unmodifiable(_jobs));
    }
    onQueueChanged?.call();
  }
}
