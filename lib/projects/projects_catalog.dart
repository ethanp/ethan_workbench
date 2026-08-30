import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_trigger.dart';
import '../phone/deploy_http_client.dart';
import 'deployable_project.dart';
import 'source_changes_progress.dart';

enum ProjectsCatalogLoadOutcome() {
  succeeded,
  unauthorized,
  failed,
}

/// Loads and refreshes the deployable project list (with optional change eval).
class ProjectsCatalog({
  required final DeployTrigger trigger,
  final void Function()? onCatalogChanged,
}) {
  List<DeployableProject> projects = const [];
  bool loading = true;
  bool evaluatingChanges = false;
  SourceChangesProgress? changesProgress;
  String? errorMessage;
  DateTime? lastChangesCheckedAt;

  /// User-facing message from the most recent failed load (for snackbars).
  String? lastFailureMessage;

  /// Incremented on each [load] so a slower earlier refresh cannot clobber.
  var _loadEpoch = 0;

  bool get hasProjects => projects.isNotEmpty;

  /// Instant left-panel update: this platform is current as of [job.finishedAt].
  void applySuccessfulDeploy(DeployJob job) {
    if (job.status != DeployJobStatus.succeeded) return;
    final deployedAt = job.finishedAt ?? DateTime.now();
    projects = [
      for (final project in projects)
        if (project.projectId == job.projectId)
          project.withSuccessfulDeploy(
            platform: job.platform,
            deployedAt: deployedAt,
          )
        else
          project,
    ]..sort((left, right) => left.compareByChangeThenName(right));
    onCatalogChanged?.call();
  }

  Future<ProjectsCatalogLoadOutcome> load({
    required bool evaluateChanges,
  }) async {
    final loadEpoch = ++_loadEpoch;
    loading = true;
    evaluatingChanges = evaluateChanges;
    changesProgress = null;
    errorMessage = null;
    lastFailureMessage = null;
    onCatalogChanged?.call();

    try {
      final loaded = evaluateChanges
          ? await trigger.evaluateSourceChanges(
              onProgress: (progress) {
                if (loadEpoch != _loadEpoch) return;
                changesProgress = progress;
                onCatalogChanged?.call();
              },
            )
          : await trigger.listProjects();
      if (loadEpoch != _loadEpoch) {
        return ProjectsCatalogLoadOutcome.succeeded;
      }
      projects = loaded;
      loading = false;
      evaluatingChanges = false;
      changesProgress = null;
      if (evaluateChanges) {
        lastChangesCheckedAt = DateTime.now();
      }
      onCatalogChanged?.call();
      return ProjectsCatalogLoadOutcome.succeeded;
    } on ServerRequestException catch (error) {
      if (loadEpoch != _loadEpoch) {
        return ProjectsCatalogLoadOutcome.succeeded;
      }
      loading = false;
      evaluatingChanges = false;
      changesProgress = null;
      onCatalogChanged?.call();
      if (error.isUnauthorized) {
        return ProjectsCatalogLoadOutcome.unauthorized;
      }
      lastFailureMessage = error.message;
      final hint = trigger.unreachableHint;
      errorMessage = evaluateChanges
          ? error.message
          : (hint == null ? error.message : '${error.message}\n\n$hint');
      return ProjectsCatalogLoadOutcome.failed;
    } catch (error) {
      if (loadEpoch != _loadEpoch) {
        return ProjectsCatalogLoadOutcome.succeeded;
      }
      loading = false;
      evaluatingChanges = false;
      changesProgress = null;
      lastFailureMessage = error.toString();
      errorMessage = error.toString();
      onCatalogChanged?.call();
      return ProjectsCatalogLoadOutcome.failed;
    }
  }

  Future<ProjectsCatalogLoadOutcome> evaluateSourceChangesIfIdle() {
    if (evaluatingChanges || loading) {
      return Future.value(ProjectsCatalogLoadOutcome.succeeded);
    }
    return load(evaluateChanges: true);
  }

  List<DeployPlatform> platformsFor(DeployableProject project) {
    // Always reserve a slot per preferred platform so rows align; unsupported
    // platforms render as a muted placeholder in [ProjectWorkbenchRow].
    return List<DeployPlatform>.of(trigger.preferredPlatforms);
  }
}
