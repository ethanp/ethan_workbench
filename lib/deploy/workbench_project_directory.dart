import '../projects/deploy_source_hasher.dart';
import '../projects/project_scanner.dart';
import '../projects/source_changes_progress.dart';
import '../projects/workbench_project.dart';
import '../sync/deploy_ledger.dart';
import 'deploy_platform.dart';

/// Lists workbench projects and evaluates deploy source-change status.
class WorkbenchProjectDirectory({
  required final List<String> flutterRoots,
  final Future<WorkbenchProject?> Function(String projectId)? _resolveProject,
}) {
  DeployLedger? _ledger;

  void attachLedger(DeployLedger? ledger) {
    _ledger = ledger;
  }

  Future<List<WorkbenchProject>> listProjects() async {
    final projects = await ProjectCatalog(flutterRoots: flutterRoots)
        .listProjects();
    return _enrichWithLedger(projects);
  }

  Future<WorkbenchProject?> find(String projectId) async {
    final override = _resolveProject;
    if (override != null) return override(projectId);
    final projects = await listProjects();
    for (final project in projects) {
      if (project.projectId == projectId) return project;
    }
    return null;
  }

  Future<List<WorkbenchProject>> evaluateSourceChanges({
    void Function(SourceChangesProgress progress)? onProgress,
  }) async {
    final projects = await listProjects();
    onProgress?.call(
      SourceChangesProgress(completed: 0, total: projects.length),
    );
    final hashMemo = DeploySourceHashMemo();
    final evaluatedProjects = <WorkbenchProject>[];
    for (var index = 0; index < projects.length; index++) {
      final project = projects[index];
      if (project.isDeployable) {
        await Future<void>.delayed(Duration.zero);
        evaluatedProjects.add(
          project.copyWith(
            sourceStatus: await DeploySourceHasher.statusesFor(
              projectPath: project.path,
              platforms: project.platforms,
              memo: hashMemo,
            ),
          ),
        );
      } else {
        evaluatedProjects.add(project);
      }
      onProgress?.call(
        SourceChangesProgress(
          completed: index + 1,
          total: projects.length,
          projectName: project.name,
        ),
      );
    }
    evaluatedProjects.sort(
      (left, right) => left.compareByChangeThenName(right),
    );
    return evaluatedProjects;
  }

  Future<List<WorkbenchProject>> _enrichWithLedger(
    List<WorkbenchProject> projects,
  ) async {
    final ledger = _ledger;
    if (ledger == null) return projects;
    final enrichedProjects = <WorkbenchProject>[];
    for (final project in projects) {
      final ledgerTimes = await ledger.lastDeployedAtFor(project.projectId);
      if (ledgerTimes.isEmpty) {
        enrichedProjects.add(project);
        continue;
      }
      final mergedDeployTimes = <DeployPlatform, DateTime?>{
        ...project.lastDeployedAt,
      };
      for (final entry in ledgerTimes.entries) {
        mergedDeployTimes[entry.key] = _laterDate(
          entry.value,
          mergedDeployTimes[entry.key],
        );
      }
      enrichedProjects.add(project.copyWith(lastDeployedAt: mergedDeployTimes));
    }
    return enrichedProjects;
  }

  DateTime? _laterDate(DateTime? left, DateTime? right) {
    if (left == null) return right;
    if (right == null) return left;
    return left.isAfter(right) ? left : right;
  }
}
