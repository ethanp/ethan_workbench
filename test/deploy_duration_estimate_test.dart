import 'package:ethan_workbench/deploy/deploy_duration_estimate.dart';
import 'package:ethan_workbench/deploy/deploy_job.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/deploy/deploy_run_record.dart';
import 'package:flutter_test/flutter_test.dart';

DeployRunRecord _run({
  required String projectId,
  required Duration elapsed,
  DeployPlatform platform = DeployPlatform.macos,
  bool force = false,
  DeployJobStatus status = DeployJobStatus.succeeded,
}) {
  final started = DateTime(2026, 1, 1);
  return DeployRunRecord(
    runId: 'r-${elapsed.inSeconds}',
    projectId: projectId,
    projectName: projectId,
    platform: platform,
    force: force,
    status: status,
    startedAt: started,
    finishedAt: started.add(elapsed),
  );
}

void main() {
  test('medianSuccessful uses successful runs for project and platform', () {
    final typical = DeployDurationEstimate.medianSuccessful(
      runs: [
        _run(projectId: 'a', elapsed: const Duration(seconds: 30)),
        _run(projectId: 'a', elapsed: const Duration(seconds: 90)),
        _run(projectId: 'a', elapsed: const Duration(seconds: 60)),
        _run(projectId: 'b', elapsed: const Duration(seconds: 10)),
        _run(
          projectId: 'a',
          elapsed: const Duration(seconds: 5),
          status: DeployJobStatus.failed,
        ),
      ],
      projectId: 'a',
      platform: DeployPlatform.macos,
    );
    expect(typical, const Duration(seconds: 60));
  });

  test('medianSuccessful prefers force-matched samples when enough exist', () {
    final typical = DeployDurationEstimate.medianSuccessful(
      runs: [
        _run(projectId: 'a', elapsed: const Duration(seconds: 40), force: true),
        _run(projectId: 'a', elapsed: const Duration(seconds: 50), force: true),
        _run(projectId: 'a', elapsed: const Duration(seconds: 200)),
        _run(projectId: 'a', elapsed: const Duration(seconds: 220)),
      ],
      projectId: 'a',
      platform: DeployPlatform.macos,
      force: true,
    );
    expect(typical, const Duration(seconds: 45));
  });

  test('remaining is typical minus elapsed, floored at zero', () {
    final started = DateTime(2026, 1, 1, 12);
    expect(
      DeployDurationEstimate.remaining(
        typical: const Duration(minutes: 2),
        startedAt: started,
        now: started.add(const Duration(seconds: 40)),
      ),
      const Duration(seconds: 80),
    );
    expect(
      DeployDurationEstimate.remaining(
        typical: const Duration(minutes: 1),
        startedAt: started,
        now: started.add(const Duration(minutes: 3)),
      ),
      Duration.zero,
    );
  });
}
