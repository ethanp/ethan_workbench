import '../projects/deployable_project.dart';
import 'deploy_job.dart';
import 'deploy_platform.dart';

/// Shared entry point for the projects UI — phone (remote) or Mac (in-process).
class DeployTrigger {
  const DeployTrigger({
    required this.listProjects,
    required this.evaluateSourceChanges,
    required this.startDeploy,
    required this.fetchJob,
    this.onUnauthorized,
    this.onUnpair,
    this.showUnpair = false,
    this.showLineAgeAnalysis = false,
    this.title = 'Deploy',
    this.unreachableHint,
    this.preferredPlatforms = const [DeployPlatform.ios, DeployPlatform.macos],
  });

  final Future<List<DeployableProject>> Function() listProjects;
  final Future<List<DeployableProject>> Function() evaluateSourceChanges;
  final Future<DeployJob> Function({
    required String projectId,
    required DeployPlatform platform,
    bool force,
  })
  startDeploy;
  final Future<DeployJob> Function(String jobId) fetchJob;
  final Future<void> Function()? onUnauthorized;
  final Future<void> Function()? onUnpair;
  final bool showUnpair;
  final bool showLineAgeAnalysis;
  final String title;
  final String? unreachableHint;
  final List<DeployPlatform> preferredPlatforms;
}
