import '../deploy/deploy_platform.dart';
import '../deploy/deploy_trigger.dart';
import '../phone/deploy_http_client.dart';
import 'deployable_project.dart';

enum ProjectsCatalogLoadOutcome { succeeded, unauthorized, failed }

/// Loads and refreshes the deployable project list (with optional change eval).
class ProjectsCatalog {
  ProjectsCatalog({required this.trigger});

  final DeployTrigger trigger;

  List<DeployableProject> projects = const [];
  bool loading = true;
  bool evaluatingChanges = false;
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
    errorMessage = null;
    lastFailureMessage = null;

    try {
      final loaded = evaluateChanges
          ? await trigger.evaluateSourceChanges()
          : await trigger.listProjects();
      projects = loaded;
      loading = false;
      evaluatingChanges = false;
      if (evaluateChanges) {
        lastChangesCheckedAt = DateTime.now();
      }
      return ProjectsCatalogLoadOutcome.succeeded;
    } on AgentRequestException catch (error) {
      loading = false;
      evaluatingChanges = false;
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
      lastFailureMessage = error.toString();
      errorMessage = error.toString();
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
    return trigger.preferredPlatforms.where(project.supports).toList();
  }
}
