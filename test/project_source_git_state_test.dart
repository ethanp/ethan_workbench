import 'dart:io';

import 'package:ethan_workbench/line_age/project_source.dart';
import 'package:ethan_workbench/line_age/project_source_git_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('an untouched checkout reads the same git state twice', () async {
    final root = await _committedGitTree();
    expect(await _readGitState(root), await _readGitState(root));
    expect((await _readGitState(root)).uncommittedFileStamps, isEmpty);
  });

  test('editing a committed file changes git state', () async {
    final root = await _committedGitTree();
    final before = await _readGitState(root);
    File(path.join(root.path, 'lib', 'a.dart'))
        .writeAsStringSync('class A2 {}\n');

    final after = await _readGitState(root);
    expect(after, isNot(before));
    expect(after.uncommittedFileStamps.keys, ['lib/a.dart']);
  });

  test('adding an untracked Swift file changes git state', () async {
    final root = await _committedGitTree();
    final before = await _readGitState(root);
    File(path.join(root.path, 'macos', 'Runner', 'AppDelegate.swift'))
      ..createSync(recursive: true)
      ..writeAsStringSync('import Cocoa\n');

    final after = await _readGitState(root);
    expect(after, isNot(before));
    expect(after.uncommittedFileStamps.keys, [
      'macos/Runner/AppDelegate.swift',
    ]);
  });

  test(
    'files to reblame are those touched by new commits or uncommitted',
    () async {
      final root = await _committedGitTree();
      final analyzed = await _readGitState(root);
      File(path.join(root.path, 'lib', 'a.dart'))
          .writeAsStringSync('class A2 {}\n');
      await _git(root, ['commit', '-am', 'edit a']);
      File(path.join(root.path, 'lib', 'c.dart'))
          .writeAsStringSync('class C {}\n');

      final current = await _readGitState(root);
      expect(await current.pathsToReblameSince(analyzed, gitRoot: root.path), {
        'lib/a.dart',
        'lib/c.dart',
      });
    },
  );

  test('a rewritten history means every file is reblamed', () async {
    final root = await _committedGitTree();
    final analyzed = await _readGitState(root);
    await _git(root, ['commit', '--amend', '-m', 'reworded']);

    final current = await _readGitState(root);
    expect(
      await current.pathsToReblameSince(analyzed, gitRoot: root.path),
      isNull,
    );
  });

  test('git state round-trips through JSON', () async {
    final root = await _committedGitTree();
    File(path.join(root.path, 'lib', 'a.dart'))
        .writeAsStringSync('class A2 {}\n');
    final gitState = await _readGitState(root);
    expect(ProjectSourceGitState.fromJson(gitState.toJson()), gitState);
  });
}

Future<ProjectSourceGitState> _readGitState(Directory root) =>
    ProjectSourceGitState.read(ProjectSource.at(root.path));

Future<Directory> _committedGitTree() async {
  final root = Directory.systemTemp.createTempSync('project_source_git_state_');
  addTearDown(() => root.deleteSync(recursive: true));
  await _git(root, ['init']);
  await _git(root, ['config', 'user.email', 'test@example.com']);
  await _git(root, ['config', 'user.name', 'Test']);
  File(path.join(root.path, 'lib', 'a.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('class A {}\n');
  File(path.join(root.path, 'lib', 'b.dart')).writeAsStringSync('class B {}\n');
  await _git(root, ['add', '.']);
  await _git(root, ['commit', '-m', 'init']);
  return root;
}

Future<void> _git(Directory root, List<String> args) async {
  final process = await Process.run('git', args, workingDirectory: root.path);
  expect(process.exitCode, 0, reason: '${args.join(' ')}: ${process.stderr}');
}
