import 'dart:async';
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
    'two concurrent callers share one analysis and the same result',
    () async {
      final root = _dartTree();
      final cache = LineAgeCache.instance;
      final release = Completer<void>();
      var starts = 0;
      final shared = _report(totalLines: 17);
      cache.resetForTest(
        analyzeOverride: (repoPath, onProgress) async {
          starts++;
          await release.future;
          return shared;
        },
      );

      final first = cache.analyzeOrCached(root.path);
      final second = cache.analyzeOrCached(root.path);
      await Future<void>.delayed(Duration.zero);
      expect(starts, 1);
      release.complete();

      final firstReport = await first;
      final secondReport = await second;
      expect(identical(firstReport, shared), isTrue);
      expect(identical(secondReport, shared), isTrue);
    },
  );

  test('failure clears in-flight state so a later retry runs again', () async {
    final root = _dartTree();
    final cache = LineAgeCache.instance;
    var starts = 0;
    cache.resetForTest(
      analyzeOverride: (repoPath, onProgress) async {
        starts++;
        if (starts == 1) throw StateError('blame failed');
        return _report(totalLines: 8);
      },
    );

    await expectLater(
      cache.analyzeOrCached(root.path),
      throwsA(isA<StateError>()),
    );
    final retry = await cache.analyzeOrCached(root.path);
    expect(starts, 2);
    expect(retry.totalLines, 8);
  });

  test('cancel fails every waiter and a later retry starts fresh', () async {
    final root = _dartTree();
    final cache = LineAgeCache.instance;
    final hang = Completer<LineAgeReport>();
    var starts = 0;
    cache.resetForTest(
      analyzeOverride: (repoPath, onProgress) {
        starts++;
        return hang.future;
      },
    );

    final first = cache.analyzeOrCached(root.path);
    final second = cache.analyzeOrCached(root.path);
    await Future<void>.delayed(Duration.zero);
    expect(starts, 1);
    cache.cancelAnalyze(root.path);

    await expectLater(first, throwsA(isA<StateError>()));
    await expectLater(second, throwsA(isA<StateError>()));

    cache.resetForTest(
      analyzeOverride: (repoPath, onProgress) async {
        starts++;
        return _report(totalLines: 3);
      },
    );
    final retry = await cache.analyzeOrCached(root.path);
    expect(starts, 2);
    expect(retry.totalLines, 3);
  });

  test('different roots still analyze independently', () async {
    final firstRoot = _dartTree();
    final secondRoot = _dartTree();
    final cache = LineAgeCache.instance;
    final release = Completer<void>();
    final startedRoots = <String>[];
    cache.resetForTest(
      analyzeOverride: (repoPath, onProgress) async {
        startedRoots.add(repoPath);
        await release.future;
        return _report(totalLines: startedRoots.length);
      },
    );

    final first = cache.analyzeOrCached(firstRoot.path);
    final second = cache.analyzeOrCached(secondRoot.path);
    await Future<void>.delayed(Duration.zero);
    expect(startedRoots, hasLength(2));
    release.complete();
    await Future.wait([first, second]);
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
