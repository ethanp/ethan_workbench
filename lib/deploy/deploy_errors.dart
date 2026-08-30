import 'deploy_job.dart';

class const DeployAlreadyRunning({
  required final String projectName,
  required final String jobId,
  required final String statusName,
  final DeployJob? job,
}) implements Exception {
  @override
  String toString() =>
      'A deploy is already running: $projectName ($statusName, $jobId)';
}

/// Same project+platform is already sitting in the wait queue.
class const DeployAlreadyQueued(final DeployJob job) implements Exception {
  @override
  String toString() =>
      'A deploy is already queued: ${job.projectName} (${job.platform.label})';
}

class const UnknownProject(final String projectId) implements Exception {
  @override
  String toString() => 'Unknown project: $projectId';
}

class const DeployScriptMissing(final String deployRbPath)
    implements Exception {
  @override
  String toString() => 'deploy.rb not found at $deployRbPath';
}

class const UnsupportedDeployPlatform({
  required final String projectName,
  required final String platformLabel,
}) implements Exception {
  @override
  String toString() => '$projectName cannot deploy to $platformLabel';
}

class const DeployJobNotFound(final String jobId) implements Exception {
  @override
  String toString() => 'Job not found: $jobId';
}
