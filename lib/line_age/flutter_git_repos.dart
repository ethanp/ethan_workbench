import 'dart:io';

import 'package:path/path.dart' as path;

/// Immediate git checkouts under configured Flutter roots (one color per repo).
class FlutterGitRepos({required final List<String> flutterRoots}) {
  List<String>? _gitRoots;

  /// Absolute git-root paths, A–Z by folder name. Nested checkouts are ignored.
  List<String> get gitRoots => _gitRoots ??= _discoverGitRoots();

  List<String> _discoverGitRoots() {
    final roots = <String>[];
    final seen = <String>{};
    for (final flutterRoot in flutterRoots) {
      _collectImmediateGitRoots(flutterRoot, roots, seen);
    }
    roots.sort(
      (left, right) => path
          .basename(left)
          .toLowerCase()
          .compareTo(path.basename(right).toLowerCase()),
    );
    return roots;
  }

  void _collectImmediateGitRoots(
    String flutterRoot,
    List<String> roots,
    Set<String> seen,
  ) {
    final directory = Directory(flutterRoot);
    if (!directory.existsSync()) return;
    late final List<FileSystemEntity> children;
    try {
      children = directory.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final entity in children) {
      if (entity is! Directory) continue;
      if (!_isGitCheckout(entity.path)) continue;
      final normalized = path.normalize(entity.absolute.path);
      if (seen.add(normalized)) roots.add(normalized);
    }
  }

  static bool _isGitCheckout(String directoryPath) {
    final gitMarker = path.join(directoryPath, '.git');
    return Directory(gitMarker).existsSync() || File(gitMarker).existsSync();
  }
}
