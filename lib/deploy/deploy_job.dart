import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';

import 'deploy_checklist.dart';
import 'deploy_platform.dart';

enum DeployJobStatus {
  queued(statusTone: EStatusTone.warning),
  running(statusTone: EStatusTone.accent),
  succeeded(statusTone: EStatusTone.success),
  failed(statusTone: EStatusTone.danger);

  const DeployJobStatus({required this.statusTone});

  final EStatusTone statusTone;

  String get pillLabel => nameAsCapitalizedWords;

  static DeployJobStatus fromName(String name) {
    return DeployJobStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => DeployJobStatus.failed,
    );
  }

  bool get isTerminal =>
      this == DeployJobStatus.succeeded || this == DeployJobStatus.failed;
}

class DeployJob {
  final String jobId;
  final String projectId;
  final String projectName;
  final DeployPlatform platform;
  final bool force;
  final DeployJobStatus status;
  final String log;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final int? exitCode;
  final List<DeployChecklistItem> checklist;

  const DeployJob({
    required this.jobId,
    required this.projectId,
    required this.projectName,
    required this.platform,
    required this.force,
    required this.status,
    required this.log,
    required this.createdAt,
    this.finishedAt,
    this.exitCode,
    this.checklist = const [],
  });

  factory DeployJob.fromJson(Map<String, dynamic> json) {
    final checklistJson = json['checklist'] as List<dynamic>?;
    return DeployJob(
      jobId: json['jobId'] as String,
      projectId: json['projectId'] as String,
      projectName: json['projectName'] as String,
      platform: DeployPlatform.fromName(
        json['platform'] as String? ?? DeployPlatform.ios.name,
      ),
      force: json['force'] as bool? ?? false,
      status: DeployJobStatus.fromName(json['status'] as String),
      log: json['log'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.parse(json['finishedAt'] as String),
      exitCode: json['exitCode'] as int?,
      checklist: checklistJson == null
          ? const []
          : [
              for (final item in checklistJson)
                DeployChecklistItem.fromJson(item as Map<String, dynamic>),
            ],
    );
  }

  Map<String, dynamic> toJson() => {
    'jobId': jobId,
    'projectId': projectId,
    'projectName': projectName,
    'platform': platform.name,
    'force': force,
    'status': status.name,
    'log': log,
    'createdAt': createdAt.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'exitCode': exitCode,
    'checklist': checklist.map((item) => item.toJson()).toList(),
  };

  DeployJob copyWith({
    DeployJobStatus? status,
    String? log,
    DateTime? finishedAt,
    int? exitCode,
    List<DeployChecklistItem>? checklist,
  }) {
    return DeployJob(
      jobId: jobId,
      projectId: projectId,
      projectName: projectName,
      platform: platform,
      force: force,
      status: status ?? this.status,
      log: log ?? this.log,
      createdAt: createdAt,
      finishedAt: finishedAt ?? this.finishedAt,
      exitCode: exitCode ?? this.exitCode,
      checklist: checklist ?? this.checklist,
    );
  }

  /// Compact snapshot for deploy-stream diagnostics.
  String get debugSummary {
    final checklistSummary = checklist.isEmpty
        ? 'none'
        : checklist.map((item) => '${item.id}:${item.status.name}').join(',');
    return '$jobId $projectName/${platform.name} ${status.name} '
        'log=${log.length}c checklist=[$checklistSummary]';
  }
}
