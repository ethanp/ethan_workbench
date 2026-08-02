import 'package:ethan_sync/ethan_sync.dart';
import 'package:powersync/powersync.dart';

import '../deploy/deploy_checklist.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_run_record.dart';

/// Persists deploy runs/state into the synced PowerSync ledger.
class DeployLedger {
  DeployLedger(this._powerSync);

  final PowerSyncDatabase _powerSync;

  Future<void> recordRunStarted(DeployJob job) async {
    await _powerSync.upsert('deploy_runs', {
      'id': job.jobId,
      'project_id': job.projectId,
      'project_name': job.projectName,
      'platform': job.platform.name,
      'force': job.force ? 1 : 0,
      'status': job.status.name,
      'source_hash': null,
      'started_at': job.createdAt.millisecondsSinceEpoch,
      'finished_at': null,
      'exit_code': null,
    });
  }

  Future<void> recordRunFinished(DeployJob job, {String? sourceHash}) async {
    final finishedAt = job.finishedAt ?? DateTime.now();
    await _powerSync.upsert('deploy_runs', {
      'id': job.jobId,
      'project_id': job.projectId,
      'project_name': job.projectName,
      'platform': job.platform.name,
      'force': job.force ? 1 : 0,
      'status': job.status.name,
      'source_hash': sourceHash,
      'started_at': job.createdAt.millisecondsSinceEpoch,
      'finished_at': finishedAt.millisecondsSinceEpoch,
      'exit_code': job.exitCode,
    });

    final stateId = '${job.projectId}:${job.platform.name}';
    final previous = await _powerSync.getOptional(
      'SELECT last_deployed_at, source_hash FROM deploy_state WHERE id = ?',
      [stateId],
    );
    final skipped = job.checklist.any(
      (item) => item.status == DeployChecklistItemStatus.skipped,
    );
    final lastDeployedAt = job.status == DeployJobStatus.succeeded && !skipped
        ? finishedAt.millisecondsSinceEpoch
        : previous?['last_deployed_at'] as int?;

    await _powerSync.upsert('deploy_state', {
      'id': stateId,
      'project_id': job.projectId,
      'platform': job.platform.name,
      'source_hash': sourceHash ?? previous?['source_hash'],
      'last_status': job.status.name,
      'last_deployed_at': lastDeployedAt,
      'last_run_id': job.jobId,
    });
  }

  /// Newest deploy runs first (activity history).
  Future<List<DeployRunRecord>> listRecentRuns({int limit = 100}) async {
    final rows = await _powerSync.getAll(
      'SELECT id, project_id, project_name, platform, force, status, '
      'started_at, finished_at, exit_code '
      'FROM deploy_runs ORDER BY started_at DESC LIMIT ?',
      [limit],
    );
    return [
      for (final row in rows) DeployRunRecord.fromLedgerRow(row),
    ];
  }

  /// Latest successful deploy times keyed by platform, for one project.
  Future<Map<DeployPlatform, DateTime?>> lastDeployedAtFor(
    String projectId,
  ) async {
    final rows = await _powerSync.getAll(
      'SELECT platform, last_deployed_at, last_status FROM deploy_state '
      'WHERE project_id = ?',
      [projectId],
    );
    final lastDeployedAt = <DeployPlatform, DateTime?>{};
    for (final row in rows) {
      final platform = DeployPlatform.fromName(row['platform'] as String);
      final status = row['last_status'] as String?;
      final millis = row['last_deployed_at'] as int?;
      if (status == DeployJobStatus.succeeded.name && millis != null) {
        lastDeployedAt[platform] = DateTime.fromMillisecondsSinceEpoch(millis);
      } else if (millis != null) {
        lastDeployedAt[platform] = DateTime.fromMillisecondsSinceEpoch(millis);
      }
    }
    return lastDeployedAt;
  }
}
