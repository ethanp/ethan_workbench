class DeployAlreadyRunning implements Exception {
  final String projectName;
  final String jobId;
  final String statusName;

  const DeployAlreadyRunning({
    required this.projectName,
    required this.jobId,
    required this.statusName,
  });

  @override
  String toString() =>
      'A deploy is already running: $projectName ($statusName, $jobId)';
}

class UnknownProject implements Exception {
  final String projectId;

  const UnknownProject(this.projectId);

  @override
  String toString() => 'Unknown project: $projectId';
}

class DeployScriptMissing implements Exception {
  final String deployRbPath;

  const DeployScriptMissing(this.deployRbPath);

  @override
  String toString() => 'deploy.rb not found at $deployRbPath';
}

class UnsupportedDeployPlatform implements Exception {
  final String projectName;
  final String platformLabel;

  const UnsupportedDeployPlatform({
    required this.projectName,
    required this.platformLabel,
  });

  @override
  String toString() => '$projectName cannot deploy to $platformLabel';
}

class DeployJobNotFound implements Exception {
  final String jobId;

  const DeployJobNotFound(this.jobId);

  @override
  String toString() => 'Job not found: $jobId';
}
