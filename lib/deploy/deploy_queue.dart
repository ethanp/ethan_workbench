import 'deploy_job.dart';

import 'package:ethan_utils/ethan_utils.dart';

/// Waiting jobs plus whether restart after queue is armed.
class const DeployQueue({
  final List<DeployJob> waiting = const [],
  final bool restartAfterQueue = false,
}) {
  factory fromJson(Map<String, dynamic> json) {
    final jobMaps = json['jobs'] as List<dynamic>? ?? const [];
    return DeployQueue(
      waiting: jobMaps.mapL(
        (jobMap) => DeployJob.fromJson(jobMap as Map<String, dynamic>),
      ),
      restartAfterQueue: json['restartAfterQueue'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'jobs': waiting.map((job) => job.toJson()).toList(),
    'restartAfterQueue': restartAfterQueue,
  };
}
