import '../commit/uncommitted_changes_cache.dart';
import '../line_age/flutter_git_repos.dart';
import '../line_age/line_age_cache.dart';

/// Line age and uncommitted-change caches for the projects homescreen.
class HomescreenSourceCache({required final void Function() onChanged}) {
  Future<void> loadPersistedLineAge() async {
    await LineAgeCache.instance.ensureLoaded();
    onChanged();
  }

  Future<void> refreshUncommitted(Iterable<String> projectPaths) async {
    await UncommittedChangesCache.instance.refreshAll(projectPaths);
  }

  Future<void> blameDistinctGitRoots({required List<String> flutterRoots}) async {
    final analyzePaths = FlutterGitRepos(flutterRoots: flutterRoots).gitRoots;
    await Future.wait(analyzePaths.map(_analyzeOrCachedOneGitRoot));
    onChanged();
  }

  Future<void> _analyzeOrCachedOneGitRoot(String repoPath) async {
    try {
      await LineAgeCache.instance.analyzeOrCached(repoPath);
    } catch (_) {
      // Keep other projects blaming; Line age subtitle stays "…" on failure.
    }
  }

  void listenToUncommittedChanges() {
    UncommittedChangesCache.instance.addListener(_notify);
  }

  void stopListeningToUncommittedChanges() {
    UncommittedChangesCache.instance.removeListener(_notify);
  }

  void _notify() => onChanged();
}
