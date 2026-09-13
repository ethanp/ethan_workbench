import 'dart:io';

import 'package:ethan_workbench/commit/git_working_tree.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('change counts include unstaged edits and untracked files', () async {
    final root = await _committedRepo();
    File(path.join(root.path, 'lib', 'a.dart')).writeAsStringSync(
      'class A {}\nclass B {}\n',
    );
    File(path.join(root.path, 'lib', 'extra.dart')).writeAsStringSync(
      'class Extra {}\nclass ExtraTwo {}\n',
    );

    final counts = await GitWorkingTree.at(root.path).changeCounts();
    expect(counts.isClean, isFalse);
    expect(counts.added, 3);
    expect(counts.removed, 0);
  });

  test('hasPushRemote is false without remotes and true with origin', () async {
    final root = await _committedRepo();
    expect(await GitWorkingTree.at(root.path).hasPushRemote, isFalse);

    final remote = Directory.systemTemp.createTempSync('git_remote_');
    addTearDown(() => remote.deleteSync(recursive: true));
    await _git(remote, ['init', '--bare']);
    await _git(root, ['remote', 'add', 'origin', remote.path]);
    expect(await GitWorkingTree.at(root.path).hasPushRemote, isTrue);
  });

  test('commitAll records a commit without pushing when there is no remote',
      () async {
    final root = await _committedRepo();
    File(path.join(root.path, 'lib', 'a.dart')).writeAsStringSync(
      'class A {}\nclass B {}\n',
    );
    final notices = <String>[];
    await GitWorkingTree.at(root.path).commitAll(
      message: 'Add class B',
      push: false,
      onNotice: (notice) => notices.add(notice.text),
    );

    final log = await _git(root, ['log', '-1', '--pretty=%s']);
    expect(log.trim(), 'Add class B');
    expect(notices.join('\n'), contains('Committed'));
    expect(notices.join('\n'), isNot(contains('Pushing')));
    expect((await GitWorkingTree.at(root.path).changeCounts()).isClean, isTrue);
  });

  test('commitAll pushes to origin when asked', () async {
    final root = await _committedRepo();
    final remote = Directory.systemTemp.createTempSync('git_remote_');
    addTearDown(() => remote.deleteSync(recursive: true));
    await _git(remote, ['init', '--bare']);
    await _git(root, ['remote', 'add', 'origin', remote.path]);
    File(path.join(root.path, 'lib', 'a.dart')).writeAsStringSync(
      'class A {}\nclass B {}\n',
    );

    final notices = <String>[];
    await GitWorkingTree.at(root.path).commitAll(
      message: 'Add class B',
      push: true,
      onNotice: (notice) => notices.add(notice.text),
    );

    final remoteLog = await _git(
      remote,
      ['log', '-1', '--pretty=%s'],
    );
    expect(remoteLog.trim(), 'Add class B');
    expect(notices.join('\n'), contains('Pushed'));
  });

  test('fileDiffs includes untracked files as insertions', () async {
    final root = await _committedRepo();
    File(path.join(root.path, 'lib', 'extra.dart')).writeAsStringSync(
      'class Extra {}\n',
    );
    final files = await GitWorkingTree.at(root.path).fileDiffs();
    expect(files.single.path, 'lib/extra.dart');
    expect(files.single.isUntracked, isTrue);
    expect(files.single.added, 1);
  });
}

Future<Directory> _committedRepo() async {
  final root = Directory.systemTemp.createTempSync('git_working_tree_');
  addTearDown(() => root.deleteSync(recursive: true));
  await _git(root, ['init', '-b', 'main']);
  await _git(root, ['config', 'user.email', 'test@example.com']);
  await _git(root, ['config', 'user.name', 'Test']);
  File(path.join(root.path, 'lib', 'a.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('class A {}\n');
  await _git(root, ['add', '.']);
  await _git(root, ['commit', '-m', 'init']);
  return root;
}

Future<String> _git(Directory root, List<String> args) async {
  final process = await Process.run(
    'git',
    args,
    workingDirectory: root.path,
  );
  expect(process.exitCode, 0, reason: '${args.join(' ')}: ${process.stderr}');
  return process.stdout as String;
}
