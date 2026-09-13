import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/foundation.dart';

import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_trigger.dart';
import '../phone/deploy_http_client.dart';
import 'source_changes_progress.dart';
import 'workbench_project.dart';

const _log = ELogger('ProjectsCatalog');

enum ProjectsCatalogLoadOutcome() {
  succeeded,
  unauthorized,
  failed,
}

/// Loads the projects visible for this workbench client.
class ProjectsCatalog({
  required final DeployTrigger trigger,
  final void Function()? onCatalogChanged,
}) {
  List<WorkbenchProject> projects = const [];
  bool loading = true;
  bool evaluatingChanges = false;
  final ValueNotifier<SourceChangesProgress?> changesProgress =
      ValueNotifier<SourceChangesProgress?>(null);
  String? errorMessage;
  DateTime? lastChangesCheckedAt;

  /// User-facing message from the most recent failed load (for snackbars).
  String? lastFailureMessage;

  /// Incremented on each [load] so a slower earlier refresh cannot clobber.
  var _loadEpoch = 0;

  bool get hasProjects => projects.isNotEmpty;

  /// Instant left-panel update: this platform is current as of [job.finishedAt].
  void markPlatformCurrentAfterDeploy(DeployJob job) {
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

  void dispose() {
    changesProgress.dispose();
  }

  Future<ProjectsCatalogLoadOutcome> load({
    required bool evaluateChanges,
  }) async {
    final loadEpoch = ++_loadEpoch;
    final keepShowingProjects = projects.isNotEmpty;
    loading = !keepShowingProjects;
    evaluatingChanges = evaluateChanges;
    changesProgress.value = null;
    errorMessage = null;
    lastFailureMessage = null;
    onCatalogChanged?.call();

    try {
      final loadedProjects = evaluateChanges
          ? await trigger.evaluateSourceChanges(
              onProgress: (progress) {
                if (loadEpoch != _loadEpoch) return;
                changesProgress.value = progress;
              },
            )
          : await trigger.listProjects();
      if (loadEpoch != _loadEpoch) {
        return ProjectsCatalogLoadOutcome.succeeded;
      }
      projects = trigger.showLineAgeAnalysis
          ? loadedProjects
          : loadedProjects.where((project) => project.isDeployable).toList();
      loading = false;
      evaluatingChanges = false;
      changesProgress.value = null;
      if (evaluateChanges) {
        lastChangesCheckedAt = DateTime.now();
      }
      onCatalogChanged?.call();
      return ProjectsCatalogLoadOutcome.succeeded;
    } on ServerRequestException catch (error, stackTrace) {
      if (loadEpoch != _loadEpoch) {
        return ProjectsCatalogLoadOutcome.succeeded;
      }
      loading = false;
      evaluatingChanges = false;
      changesProgress.value = null;
      onCatalogChanged?.call();
      if (error.isUnauthorized) {
        return ProjectsCatalogLoadOutcome.unauthorized;
      }
      _log.error('Project catalog load failed', error, stackTrace);
      lastFailureMessage = error.message;
      final hint = trigger.unreachableHint;
      errorMessage = evaluateChanges
          ? error.message
          : (hint == null ? error.message : '${error.message}\n\n$hint');
      return ProjectsCatalogLoadOutcome.failed;
    } catch (error, stackTrace) {
      if (loadEpoch != _loadEpoch) {
        return ProjectsCatalogLoadOutcome.succeeded;
      }
      loading = false;
      evaluatingChanges = false;
      changesProgress.value = null;
      _log.error('Project catalog load failed', error, stackTrace);
      lastFailureMessage = error.toString();
      errorMessage = error.toString();
      onCatalogChanged?.call();
      return ProjectsCatalogLoadOutcome.failed;
    }
  }

  List<DeployPlatform> platformsFor(WorkbenchProject project) {
    if (!project.isDeployable) return const [];
    // Always reserve a slot per preferred platform so rows align; unsupported
    // platforms render as a muted placeholder in [ProjectWorkbenchRow].
    return List<DeployPlatform>.of(trigger.preferredPlatforms);
  }
}
