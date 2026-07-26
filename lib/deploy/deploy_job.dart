enum DeployJobStatus {
  queued,
  running,
  succeeded,
  failed;

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
  final bool force;
  final DeployJobStatus status;
  final String log;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final int? exitCode;

  const DeployJob({
    required this.jobId,
    required this.projectId,
    required this.projectName,
    required this.force,
    required this.status,
    required this.log,
    required this.createdAt,
    this.finishedAt,
    this.exitCode,
  });

  factory DeployJob.fromJson(Map<String, dynamic> json) {
    return DeployJob(
      jobId: json['jobId'] as String,
      projectId: json['projectId'] as String,
      projectName: json['projectName'] as String,
      force: json['force'] as bool? ?? false,
      status: DeployJobStatus.fromName(json['status'] as String),
      log: json['log'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.parse(json['finishedAt'] as String),
      exitCode: json['exitCode'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'projectId': projectId,
        'projectName': projectName,
        'force': force,
        'status': status.name,
        'log': log,
        'createdAt': createdAt.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'exitCode': exitCode,
      };

  DeployJob copyWith({
    DeployJobStatus? status,
    String? log,
    DateTime? finishedAt,
    int? exitCode,
  }) {
    return DeployJob(
      jobId: jobId,
      projectId: projectId,
      projectName: projectName,
      force: force,
      status: status ?? this.status,
      log: log ?? this.log,
      createdAt: createdAt,
      finishedAt: finishedAt ?? this.finishedAt,
      exitCode: exitCode ?? this.exitCode,
    );
  }
}
