import 'package:ethan_workbench/deploy/deploy_job.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/deploy/deploy_wait_queue.dart';
import 'package:flutter_test/flutter_test.dart';

DeployJob _waitingJob(String id) {
  return DeployJob(
    jobId: id,
    projectId: id,
    projectName: id,
    platform: DeployPlatform.macos,
    force: false,
    status: DeployJobStatus.waiting,
    log: '',
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  test('moveToIndex puts a later job first in line', () {
    final queue = DeployWaitQueue();
    queue
      ..enqueue(_waitingJob('alpha'))
      ..enqueue(_waitingJob('beta'))
      ..enqueue(_waitingJob('gamma'));

    expect(queue.moveToIndex(jobId: 'gamma', toIndex: 0), isTrue);
    expect(queue.jobs.map((job) => job.jobId), ['gamma', 'alpha', 'beta']);
    expect(queue.takeNext()?.jobId, 'gamma');
  });

  test('moveToIndex no-ops when the job is already at toIndex', () {
    final queue = DeployWaitQueue();
    queue
      ..enqueue(_waitingJob('alpha'))
      ..enqueue(_waitingJob('beta'));

    expect(queue.moveToIndex(jobId: 'beta', toIndex: 1), isTrue);
    expect(queue.jobs.map((job) => job.jobId), ['alpha', 'beta']);
  });

  test('moveToIndex returns false for a missing job or bad index', () {
    final queue = DeployWaitQueue();
    queue
      ..enqueue(_waitingJob('alpha'))
      ..enqueue(_waitingJob('beta'));

    expect(queue.moveToIndex(jobId: 'missing', toIndex: 0), isFalse);
    expect(queue.moveToIndex(jobId: 'alpha', toIndex: -1), isFalse);
    expect(queue.moveToIndex(jobId: 'alpha', toIndex: 2), isFalse);
    expect(queue.jobs.map((job) => job.jobId), ['alpha', 'beta']);
  });
}
