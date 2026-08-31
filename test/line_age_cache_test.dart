import 'dart:io';

import 'package:ethan_workbench/line_age/line_age_report.dart';
import 'package:ethan_workbench/line_age/line_age_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  setUp(() => LineAgeCache.instance.resetForTest());

  test('lastStoredReport survives a dart-tree fingerprint change', () {
    final root = _dartTree();
    final cache = LineAgeCache.instance;
    final firstFingerprint = LineAgeCache.computeFingerprint(root.path);
    cache.put(
      gitRoot: root.path,
      fingerprint: firstFingerprint,
      report: _report(totalLines: 42),
    );

    expect(cache.lastStoredReport(root.path)?.totalLines, 42);
    expect(cache.isFingerprintCurrent(root.path), isTrue);

    File(path.join(root.path, 'lib', 'a.dart'))
        .writeAsStringSync('void main() { print(1); }\n');
    expect(cache.isFingerprintCurrent(root.path), isFalse);
    expect(cache.lastStoredReport(root.path)?.totalLines, 42);
  });

  test('fingerprint changes when a Swift file is added', () {
    final root = _dartTree();
    final cache = LineAgeCache.instance;
    cache.put(
      gitRoot: root.path,
      fingerprint: LineAgeCache.computeFingerprint(root.path),
      report: _report(totalLines: 7),
    );

    File(path.join(root.path, 'macos', 'Runner', 'AppDelegate.swift'))
      ..createSync(recursive: true)
      ..writeAsStringSync('import Cocoa\n');
    expect(cache.isFingerprintCurrent(root.path), isFalse);
  });

  test('fingerprint changes when file count changes', () {
    final root = _dartTree();
    final cache = LineAgeCache.instance;
    cache.put(
      gitRoot: root.path,
      fingerprint: LineAgeCache.computeFingerprint(root.path),
      report: _report(totalLines: 7),
    );

    File(path.join(root.path, 'lib', 'b.dart'))
        .writeAsStringSync('class B {}\n');
    expect(cache.isFingerprintCurrent(root.path), isFalse);
    expect(cache.lastStoredReport(root.path)?.totalLines, 7);
  });

  test(
    'analyzeOrCached returns the stored report when the fingerprint is current',
    () async {
      final root = _dartTree();
      final cache = LineAgeCache.instance;
      final stored = _report(totalLines: 99);
      cache.put(
        gitRoot: root.path,
        fingerprint: LineAgeCache.computeFingerprint(root.path),
        report: stored,
      );

      final again = await cache.analyzeOrCached(root.path);
      expect(identical(again, stored), isTrue);
    },
  );

  test('analyzeOrCached re-blames when the fingerprint is stale', () async {
    final root = await _committedGitTree();
    final cache = LineAgeCache.instance;
    cache.put(
      gitRoot: root.path,
      fingerprint: LineAgeCache.computeFingerprint(root.path),
      report: _report(totalLines: 1),
    );

    File(path.join(root.path, 'lib', 'a.dart'))
        .writeAsStringSync('void main() {}\nvoid extra() {}\n');
    await _git(root, ['add', '.']);
    await _git(root, ['commit', '-m', 'more']);

    expect(cache.isFingerprintCurrent(root.path), isFalse);
    expect(cache.lastStoredReport(root.path)?.totalLines, 1);

    final fresh = await cache.analyzeOrCached(root.path);
    expect(fresh.totalLines, greaterThan(1));
    expect(cache.isFingerprintCurrent(root.path), isTrue);
  });

  test(
    'put persists to disk and ensureLoaded restores after restart',
    () async {
      final persistenceRoot = Directory.systemTemp.createTempSync(
        'line_age_persist_',
      );
      addTearDown(() => persistenceRoot.deleteSync(recursive: true));

      final root = _dartTree();
      LineAgeCache.instance.resetForTest(persistenceDirectory: persistenceRoot);
      LineAgeCache.instance.put(
        gitRoot: root.path,
        fingerprint: LineAgeCache.computeFingerprint(root.path),
        report: _report(totalLines: 314),
      );
      await Future<void>.delayed(Duration.zero);

      LineAgeCache.instance.resetForTest(persistenceDirectory: persistenceRoot);
      await LineAgeCache.instance.ensureLoaded();
      expect(
        LineAgeCache.instance.lastStoredReport(root.path)?.totalLines,
        314,
      );
    },
  );
}

Directory _dartTree() {
  final root = Directory.systemTemp.createTempSync('line_age_cache_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(path.join(root.path, '.git')).createSync();
  File(path.join(root.path, 'lib', 'a.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('void main() {}\n');
  return root;
}

Future<Directory> _committedGitTree() async {
  final root = Directory.systemTemp.createTempSync('line_age_cache_git_');
  addTearDown(() => root.deleteSync(recursive: true));
  await _git(root, ['init']);
  await _git(root, ['config', 'user.email', 'test@example.com']);
  await _git(root, ['config', 'user.name', 'Test']);
  File(path.join(root.path, 'lib', 'a.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('void main() {}\n');
  await _git(root, ['add', '.']);
  await _git(root, ['commit', '-m', 'init']);
  return root;
}

Future<void> _git(Directory root, List<String> args) async {
  final process = await Process.run('git', args, workingDirectory: root.path);
  expect(process.exitCode, 0, reason: '${args.join(' ')}: ${process.stderr}');
}

LineAgeReport _report({required int totalLines}) {
  return LineAgeReport(
    repoName: 'tmp',
    months: const [],
    totalLinesByFile: const {},
    totalLines: totalLines,
    fileCount: 1,
  );
}
