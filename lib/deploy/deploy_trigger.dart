import '../projects/deployable_project.dart';
import '../projects/source_changes_progress.dart';
import 'deploy_job.dart';
import 'deploy_platform.dart';
import 'deploy_run_record.dart';

/// Shared entry point for the projects UI — phone (remote) or Mac (in-process).
class DeployTrigger {
  const DeployTrigger({
    required this.listProjects,
    required this.evaluateSourceChanges,
    required this.startDeploy,
    required this.fetchJob,
    required this.fetchActiveJob,
    required this.listDeployHistory,
    required this.fetchDeployQueue,
    required this.cancelQueuedDeploy,
    this.jobUpdates,
    this.queueUpdates,
    this.onUnauthorized,
    this.onUnpair,
    this.showUnpair = false,
    this.showLineAgeAnalysis = false,
    this.title = 'Deploy',
    this.unreachableHint,
    this.preferredPlatforms = const [DeployPlatform.ios, DeployPlatform.macos],
  });

  final Future<List<DeployableProject>> Function() listProjects;
  final Future<List<DeployableProject>> Function({
    void Function(SourceChangesProgress progress)? onProgress,
  })
  evaluateSourceChanges;
  final Future<DeployJob> Function({
    required String projectId,
    required DeployPlatform platform,
    bool force,
  })
  startDeploy;
  final Future<DeployJob> Function(String jobId) fetchJob;
  final Future<DeployJob?> Function() fetchActiveJob;
  final Future<List<DeployRunRecord>> Function() listDeployHistory;
  final Future<List<DeployJob>> Function() fetchDeployQueue;
  final Future<void> Function(String jobId) cancelQueuedDeploy;

  /// Live job updates when available (Mac in-process, phone via SSE).
  /// Otherwise the UI polls [fetchActiveJob] / [fetchJob].
  final Stream<DeployJob>? jobUpdates;

  /// Live wait-queue snapshots when available (Mac in-process).
  /// Otherwise the UI polls [fetchDeployQueue].
  final Stream<List<DeployJob>>? queueUpdates;
  final Future<void> Function()? onUnauthorized;
  final Future<void> Function()? onUnpair;
  final bool showUnpair;
  final bool showLineAgeAnalysis;
  final String title;
  final String? unreachableHint;
  final List<DeployPlatform> preferredPlatforms;
}
