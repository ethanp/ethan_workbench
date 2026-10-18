import 'package:flutter_test/flutter_test.dart';
import 'package:ethan_workbench/deploy/deploy_checklist.dart';
import 'package:ethan_workbench/deploy/deploy_job.dart';
import 'package:ethan_workbench/deploy/install.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';

void main() {
  group('DeployChecklist.formatElapsed', () {
    test('formats seconds then minutes', () {
      expect(DeployChecklist.formatElapsed(Duration.zero), '0s');
      expect(DeployChecklist.formatElapsed(const Duration(seconds: 3)), '3s');
      expect(
        DeployChecklist.formatElapsed(const Duration(minutes: 1, seconds: 3)),
        '1m 3s',
      );
      expect(DeployChecklist.formatElapsed(const Duration(minutes: 2)), '2m');
    });
  });

  group('DeployChecklist.advanceToPhase', () {
    final planned = DeployChecklist.planned(
      platform: DeployPlatform.ios,
      force: false,
    );
    final at = DateTime(2026, 7, 31, 12);

    test('checks off completed steps and activates the current one', () {
      final afterChecking = DeployChecklist.advanceToPhase(
        planned,
        'checking',
        at: at,
      );
      expect(afterChecking[0].status, DeployChecklistItemStatus.active);

      final afterResolving = DeployChecklist.advanceToPhase(
        afterChecking,
        'resolving',
        at: at.add(const Duration(seconds: 2)),
      );
      expect(afterResolving[0].status, DeployChecklistItemStatus.done);
      expect(afterResolving[1].status, DeployChecklistItemStatus.active);

      final afterBuilding = DeployChecklist.advanceToPhase(
        afterResolving,
        'building',
        at: at.add(const Duration(seconds: 5)),
      );
      expect(afterBuilding[0].status, DeployChecklistItemStatus.done);
      expect(afterBuilding[1].status, DeployChecklistItemStatus.done);
      expect(afterBuilding[2].status, DeployChecklistItemStatus.active);
      expect(afterBuilding[3].status, DeployChecklistItemStatus.pending);
    });

    test('skips remaining steps when unchanged', () {
      final afterChecking = DeployChecklist.advanceToPhase(
        planned,
        'checking',
        at: at,
      );
      final skipped = DeployChecklist.advanceToPhase(
        afterChecking,
        'skipped',
        at: at.add(const Duration(seconds: 1)),
      );
      expect(skipped[0].status, DeployChecklistItemStatus.done);
      expect(skipped[1].status, DeployChecklistItemStatus.skipped);
      expect(skipped[2].status, DeployChecklistItemStatus.skipped);
      expect(skipped[3].status, DeployChecklistItemStatus.skipped);
      expect(skipped[4].status, DeployChecklistItemStatus.skipped);
    });

    test('marks active step failed and skips the rest', () {
      final afterResolving = DeployChecklist.advanceToPhase(
        DeployChecklist.advanceToPhase(planned, 'checking', at: at),
        'resolving',
        at: at.add(const Duration(seconds: 2)),
      );
      final failed = DeployChecklist.advanceToPhase(
        afterResolving,
        'failed',
        at: at.add(const Duration(seconds: 10)),
      );
      expect(failed[0].status, DeployChecklistItemStatus.done);
      expect(failed[1].status, DeployChecklistItemStatus.failed);
      expect(failed[1].finishedAt, at.add(const Duration(seconds: 10)));
      expect(failed[2].status, DeployChecklistItemStatus.skipped);
      expect(failed[3].status, DeployChecklistItemStatus.skipped);
      expect(failed[4].status, DeployChecklistItemStatus.skipped);
    });
  });

  test('a failed install retries without rebuilding', () {
    final job = DeployJob(
      jobId: '1',
      projectId: 'health_notes',
      projectName: 'Health Notes',
      platform: DeployPlatform.ios,
      force: false,
      status: DeployJobStatus.failed,
      log: '',
      createdAt: DateTime(2026, 10, 4),
      checklist: const [
        DeployChecklistItem(
          id: 'building',
          label: 'Build app',
          status: DeployChecklistItemStatus.done,
        ),
        DeployChecklistItem(
          id: 'installing',
          label: 'Install on iPhone',
          status: DeployChecklistItemStatus.failed,
        ),
      ],
    );
    final retry = job.installStep?.install.retry(force: false);
    expect(retry?.modeLabel, 'Retry install');
    expect(retry?.plannedChecklist().map((item) => item.id), [
      'installing',
      'recording',
    ]);
    expect(retry?.installStep.label, 'Install on iPhone');
    final arguments = <String>[];
    retry?.install.addScriptArguments(arguments);
    expect(arguments, ['--from-install']);
  });

  test('a failed build is not an install retry', () {
    final install = Install(step: InstallStep.pending(DeployPlatform.ios));
    expect(install.retry(force: false), isNull);
  });
}
