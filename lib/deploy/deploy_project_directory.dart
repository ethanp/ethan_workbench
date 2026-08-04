import '../projects/deployable_project.dart';
import '../projects/deploy_source_hasher.dart';
import '../projects/project_scanner.dart';
import '../projects/source_changes_progress.dart';
import '../sync/deploy_ledger.dart';
import 'deploy_platform.dart';

/// Lists deployable Flutter projects and evaluates source-change status.
class DeployProjectDirectory {
  DeployProjectDirectory({
    required this.flutterRoots,
    this._resolveProject,
  });

  final List<String> flutterRoots;
  final Future<DeployableProject?> Function(String projectId)? _resolveProject;
  DeployLedger? _ledger;

  void attachLedger(DeployLedger? ledger) {
    _ledger = ledger;
  }

  Future<List<DeployableProject>> listDeployable() async {
    final projects = await ProjectCatalog(
      flutterRoots: flutterRoots,
    ).listDeployableProjects();
    return _enrichWithLedger(projects);
  }

  Future<DeployableProject?> find(String projectId) async {
    final override = _resolveProject;
    if (override != null) return override(projectId);
    final projects = await listDeployable();
    for (final project in projects) {
      if (project.projectId == projectId) return project;
    }
    return null;
  }

  /// Recomputes deploy.rb source hashes for every project/platform.
  Future<List<DeployableProject>> evaluateSourceChanges({
    void Function(SourceChangesProgress progress)? onProgress,
  }) async {
    final projects = await listDeployable();
    onProgress?.call(
      SourceChangesProgress(completed: 0, total: projects.length),
    );
    final evaluated = <DeployableProject>[];
    for (var index = 0; index < projects.length; index++) {
      final project = projects[index];
      evaluated.add(
        project.copyWith(
          sourceStatus: await DeploySourceHasher.statusesFor(
            projectPath: project.path,
            platforms: project.platforms,
          ),
        ),
      );
      onProgress?.call(
        SourceChangesProgress(
          completed: index + 1,
          total: projects.length,
          projectName: project.name,
        ),
      );
    }
    evaluated.sort((left, right) {
      final leftChanged = left.hasChangedSources ? 0 : 1;
      final rightChanged = right.hasChangedSources ? 0 : 1;
      if (leftChanged != rightChanged) {
        return leftChanged.compareTo(rightChanged);
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return evaluated;
  }

  Future<List<DeployableProject>> _enrichWithLedger(
    List<DeployableProject> projects,
  ) async {
    final ledger = _ledger;
    if (ledger == null) return projects;
    final enriched = <DeployableProject>[];
    for (final project in projects) {
      final ledgerTimes = await ledger.lastDeployedAtFor(project.projectId);
      if (ledgerTimes.isEmpty) {
        enriched.add(project);
        continue;
      }
      final merged = <DeployPlatform, DateTime?>{...project.lastDeployedAt};
      for (final entry in ledgerTimes.entries) {
        merged[entry.key] = entry.value ?? merged[entry.key];
      }
      enriched.add(project.copyWith(lastDeployedAt: merged));
    }
    return enriched;
  }
}
