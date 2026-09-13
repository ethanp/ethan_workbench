import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../line_age/line_age_analyzer.dart';
import 'git_working_tree.dart';
import 'uncommitted_change_counts.dart';

const _log = ELogger('UncommittedChangesCache');

/// Uncommitted +/− counts keyed by git root, refreshed on catalog load.
class UncommittedChangesCache._() extends ChangeNotifier {
  static final UncommittedChangesCache instance = UncommittedChangesCache._();

  final Map<String, UncommittedChangeCounts> _counts = {};

  /// Test hook.
  void resetForTest() {
    _counts.clear();
  }

  UncommittedChangeCounts? countsForRepoPath(String repoPath) {
    final gitRoot = LineAgeAnalyzer.findGitRoot(repoPath);
    if (gitRoot == null) return null;
    return _counts[path.normalize(gitRoot)];
  }

  String captionForRepoPath(String repoPath) =>
      countsForRepoPath(repoPath)?.caption ?? '…';

  Future<void> refresh(String repoPath, {bool notify = true}) async {
    final gitRoot = LineAgeAnalyzer.findGitRoot(repoPath);
    if (gitRoot == null) return;
    try {
      final counts = await GitWorkingTree.at(gitRoot).changeCounts();
      _counts[path.normalize(gitRoot)] = counts;
      if (notify) notifyListeners();
    } catch (error, stackTrace) {
      _log.warn('Uncommitted counts failed for $gitRoot', error, stackTrace);
    }
  }

  Future<void> refreshAll(Iterable<String> repoPaths) async {
    final roots = <String>{};
    final pathsByRoot = <String, String>{};
    for (final repoPath in repoPaths) {
      final gitRoot = LineAgeAnalyzer.findGitRoot(repoPath);
      if (gitRoot == null) continue;
      final normalized = path.normalize(gitRoot);
      if (roots.add(normalized)) pathsByRoot[normalized] = repoPath;
    }
    await Future.wait([
      for (final repoPath in pathsByRoot.values)
        refresh(repoPath, notify: false),
    ]);
    notifyListeners();
  }
}
