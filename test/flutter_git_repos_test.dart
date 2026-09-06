import 'dart:io';

import 'package:ethan_workbench/line_age/flutter_git_repos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('lists immediate git checkouts and ignores nested ones', () {
    final flutterRoot = Directory.systemTemp.createTempSync('flutter_git_repos_');
    addTearDown(() => flutterRoot.deleteSync(recursive: true));

    _gitDir(path.join(flutterRoot.path, 'workouts'));
    _gitFile(path.join(flutterRoot.path, 'worktree_style'));
    Directory(path.join(flutterRoot.path, 'no_git')).createSync();
    _gitDir(path.join(flutterRoot.path, 'viant', 'apps', 'nested_app'));

    final gitRoots = FlutterGitRepos(flutterRoots: [flutterRoot.path]).gitRoots;
    final names = [for (final gitRoot in gitRoots) path.basename(gitRoot)]
      ..sort();

    expect(names, ['workouts', 'worktree_style']);
  });

  test('skips missing flutter roots', () {
    final gitRoots = FlutterGitRepos(
      flutterRoots: ['/tmp/does-not-exist-flutter-line-age'],
    ).gitRoots;
    expect(gitRoots, isEmpty);
  });
}

void _gitDir(String repoPath) {
  Directory(path.join(repoPath, '.git')).createSync(recursive: true);
}

void _gitFile(String repoPath) {
  Directory(repoPath).createSync(recursive: true);
  File(path.join(repoPath, '.git')).writeAsStringSync('gitdir: /elsewhere');
}
