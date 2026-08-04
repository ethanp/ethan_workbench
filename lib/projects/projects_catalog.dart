import '../deploy/deploy_platform.dart';
import '../deploy/deploy_trigger.dart';
import '../phone/deploy_http_client.dart';
import 'deployable_project.dart';
import 'source_changes_progress.dart';

enum ProjectsCatalogLoadOutcome { succeeded, unauthorized, failed }

/// Loads and refreshes the deployable project list (with optional change eval).
class ProjectsCatalog {
  ProjectsCatalog({required this.trigger, this.onChanged});

  final DeployTrigger trigger;
  final void Function()? onChanged;

  List<DeployableProject> projects = const [];
  bool loading = true;
  bool evaluatingChanges = false;
  SourceChangesProgress? changesProgress;
  String? errorMessage;
  DateTime? lastChangesCheckedAt;

  /// User-facing message from the most recent failed load (for snackbars).
  String? lastFailureMessage;

  bool get hasProjects => projects.isNotEmpty;

  Future<ProjectsCatalogLoadOutcome> load({
    required bool evaluateChanges,
  }) async {
    loading = true;
    evaluatingChanges = evaluateChanges;
    changesProgress = null;
    errorMessage = null;
    lastFailureMessage = null;
    onChanged?.call();

    try {
      final loaded = evaluateChanges
          ? await trigger.evaluateSourceChanges(
              onProgress: (progress) {
                changesProgress = progress;
                onChanged?.call();
              },
            )
          : await trigger.listProjects();
      projects = loaded;
      loading = false;
      evaluatingChanges = false;
      changesProgress = null;
      if (evaluateChanges) {
        lastChangesCheckedAt = DateTime.now();
      }
      onChanged?.call();
      return ProjectsCatalogLoadOutcome.succeeded;
    } on AgentRequestException catch (error) {
      loading = false;
      evaluatingChanges = false;
      changesProgress = null;
      onChanged?.call();
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
      loading = false;
      evaluatingChanges = false;
      changesProgress = null;
      lastFailureMessage = error.toString();
      errorMessage = error.toString();
      onChanged?.call();
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
