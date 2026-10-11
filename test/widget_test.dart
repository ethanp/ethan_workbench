import 'package:flutter_test/flutter_test.dart';

import 'package:ethan_workbench/deploy/deploy_job.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/run/local_run_key.dart';
import 'package:ethan_workbench/run/local_run_state.dart';

void main() {
  test('DeployJobStatus terminal and waiting flags', () {
    expect(DeployJobStatus.succeeded.isTerminal, isTrue);
    expect(DeployJobStatus.failed.isTerminal, isTrue);
    expect(DeployJobStatus.running.isTerminal, isFalse);
    expect(DeployJobStatus.waiting.isWaiting, isTrue);
    expect(DeployJobStatus.waiting.isActiveRunner, isFalse);
    expect(DeployJobStatus.queued.isActiveRunner, isTrue);
    expect(DeployJobStatus.running.isActiveRunner, isTrue);
  });

  test('DeployJob queue chrome ignores log growth', () {
    final running = DeployJob(
      jobId: 'job-1',
      projectId: 'book_track',
      projectName: 'book_track',
      platform: DeployPlatform.ios,
      force: false,
      status: DeployJobStatus.running,
      log: 'a',
      createdAt: DateTime(2026, 1, 1),
    );
    expect(running.sameQueueChromeAs(running.copyWith(log: 'ab')), isTrue);
    expect(
      running.sameQueueChromeAs(
        running.copyWith(status: DeployJobStatus.succeeded),
      ),
      isFalse,
    );
  });

  test('LocalRunState row chrome ignores log growth', () {
    const running = LocalRunState(
      status: LocalRunStatus.running,
      log: 'a',
      readyForKeyCommands: true,
      projectId: 'book_track',
      deviceKey: 'meSim',
    );
    expect(running.sameRowChromeAs(running.copyWith(log: 'ab')), isTrue);
    expect(
      running.sameRowChromeAs(
        running.copyWith(readyForKeyCommands: false),
      ),
      isFalse,
    );
    expect(
      running.runKey,
      LocalRunKey(projectId: 'book_track', deviceKey: 'meSim'),
    );
  });
}
