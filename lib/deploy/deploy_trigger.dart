import '../projects/source_changes_progress.dart';
import '../projects/workbench_project.dart';
import 'deploy_job.dart';
import 'deploy_platform.dart';
import 'deploy_run_record.dart';

/// Shared entry point for the projects UI — phone (remote) or Mac (in-process).
class const DeployTrigger({
  required final Future<List<WorkbenchProject>> Function() listProjects,
  required final Future<List<WorkbenchProject>> Function({
    void Function(SourceChangesProgress progress)? onProgress,
  })
  evaluateSourceChanges,
  required final Future<DeployJob> Function({
    required String projectId,
    required DeployPlatform platform,
    bool force,
  })
  startDeploy,
  required final Future<DeployJob> Function(String jobId) fetchJob,
  required final Future<DeployJob?> Function() fetchActiveJob,
  required final Future<List<DeployRunRecord>> Function() listDeployHistory,
  required final Future<List<DeployJob>> Function() fetchDeployQueue,
  required final Future<void> Function(String jobId) cancelQueuedDeploy,

  /// Live job updates when available (Mac in-process, phone via SSE).
  /// Otherwise the UI polls [fetchActiveJob] / [fetchJob].
  final Stream<DeployJob>? jobUpdates,

  /// Live wait-queue snapshots when available (Mac in-process).
  /// Otherwise the UI polls [fetchDeployQueue].
  final Stream<List<DeployJob>>? queueUpdates,
  final Future<void> Function()? onUnauthorized,
  final Future<void> Function()? onSignOut,
  final bool showSignOut = false,
  final bool showLineAgeAnalysis = false,

  /// Local Flutter checkout roots for fleet Line age (Mac only).
  final List<String> flutterRoots = const [],
  final String title = 'Deploy',
  final String? unreachableHint,
  final List<DeployPlatform> preferredPlatforms = const [
    DeployPlatform.ios,
    DeployPlatform.macos,
  ],
});
