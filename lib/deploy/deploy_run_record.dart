import 'deploy_job.dart';
import 'deploy_platform.dart';

/// One persisted deploy from the ledger (history list row).
class DeployRunRecord {
  const DeployRunRecord({
    required this.runId,
    required this.projectId,
    required this.projectName,
    required this.platform,
    required this.force,
    required this.status,
    required this.startedAt,
    this.finishedAt,
    this.exitCode,
  });

  final String runId;
  final String projectId;
  final String projectName;
  final DeployPlatform platform;
  final bool force;
  final DeployJobStatus status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int? exitCode;

  /// Wall time from start to finish, or to now while still running.
  Duration get elapsed {
    final end = finishedAt ?? DateTime.now();
    return end.difference(startedAt);
  }

  factory DeployRunRecord.fromLedgerRow(Map<String, Object?> row) {
    final finishedMillis = row['finished_at'] as int?;
    return DeployRunRecord(
      runId: row['id'] as String,
      projectId: row['project_id'] as String,
      projectName: row['project_name'] as String,
      platform: DeployPlatform.fromName(row['platform'] as String),
      force: (row['force'] as int? ?? 0) != 0,
      status: DeployJobStatus.fromName(row['status'] as String),
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        row['started_at'] as int,
      ),
      finishedAt: finishedMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(finishedMillis),
      exitCode: row['exit_code'] as int?,
    );
  }

  factory DeployRunRecord.fromJson(Map<String, dynamic> json) {
    return DeployRunRecord(
      runId: json['runId'] as String,
      projectId: json['projectId'] as String,
      projectName: json['projectName'] as String,
      platform: DeployPlatform.fromName(json['platform'] as String),
      force: json['force'] as bool? ?? false,
      status: DeployJobStatus.fromName(json['status'] as String),
      startedAt: DateTime.parse(json['startedAt'] as String),
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.parse(json['finishedAt'] as String),
      exitCode: json['exitCode'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'runId': runId,
    'projectId': projectId,
    'projectName': projectName,
    'platform': platform.name,
    'force': force,
    'status': status.name,
    'startedAt': startedAt.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'exitCode': exitCode,
  };
}
