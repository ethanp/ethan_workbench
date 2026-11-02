import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';

import 'dart:io';

import 'package:ethan_workbench/line_age/line_age_analysis_cancelled.dart';
import 'package:ethan_workbench/line_age/line_age_analyzer.dart';
import 'package:ethan_workbench/line_age/line_age_cache.dart';
import 'package:ethan_workbench/line_age/line_age_report.dart';
import 'package:ethan_workbench/line_age/project_source.dart';
import 'package:ethan_workbench/line_age/project_source_git_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  setUp(() => LineAgeCache.instance.resetForTest());

  test(
    'analyzeOrCached returns the stored report when git state is unchanged',
    () async {
      final root = await _committedGitTree();
      final cache = LineAgeCache.instance;
      final stored = _report(totalLines: 99);
      cache.put(
        gitRoot: root.path,
        measured: MeasuredLineAge(
          gitState: await ProjectSourceGitState.read(
            ProjectSource.at(root.path),
          ),
          report: stored,
        ),
      );

      final again = await cache.analyzeOrCached(root.path);
      expect(identical(again, stored), isTrue);
    },
  );

  test(
    'analyzeOrCached reblames only files changed since the stored report',
    () async {
      final root = await _committedGitTree();
      final cache = LineAgeCache.instance;
      cache.put(
        gitRoot: root.path,
        measured: MeasuredLineAge(
          gitState: await ProjectSourceGitState.read(
            ProjectSource.at(root.path),
          ),
          report: _reportAllIn2001(['lib/a.dart', 'lib/b.dart']),
        ),
      );

      File(path.join(root.path, 'lib', 'a.dart'))
          .writeAsStringSync('void main() {}\nvoid extra() {}\n');
      await _git(root, ['commit', '-am', 'more']);

      final fresh = await cache.analyzeOrCached(root.path);
      expect(_filesIn2001(fresh), ['lib/b.dart']);
      expect(fresh.totalLinesByFile['lib/a.dart'], 2);
      expect(identical(await cache.analyzeOrCached(root.path), fresh), isTrue);
    },
  );

  test(
    'analyzeOrCached reblames every file after history is rewritten',
    () async {
      final root = await _committedGitTree();
      final cache = LineAgeCache.instance;
      cache.put(
        gitRoot: root.path,
        measured: MeasuredLineAge(
          gitState: await ProjectSourceGitState.read(
            ProjectSource.at(root.path),
          ),
          report: _reportAllIn2001(['lib/a.dart', 'lib/b.dart']),
        ),
      );

      await _git(root, ['commit', '--amend', '-m', 'reworded']);

      final fresh = await cache.analyzeOrCached(root.path);
      expect(_filesIn2001(fresh), isEmpty);
      expect(fresh.totalLines, 2);
    },
  );

  test(
    'two concurrent callers share one analysis and the same result',
    () async {
      final root = _dartTree();
      final cache = LineAgeCache.instance;
      final started = Completer<void>();
      final release = Completer<void>();
      var starts = 0;
      final shared = _report(totalLines: 17);
      cache.resetForTest(
        analyzeOverride: (repoPath, onProgress) async {
          starts++;
          started.complete();
          await release.future;
          return shared;
        },
      );

      final first = cache.analyzeOrCached(root.path);
      final second = cache.analyzeOrCached(root.path);
      await started.future;
      release.complete();

      final firstReport = await first;
      final secondReport = await second;
      expect(starts, 1);
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
    final started = Completer<void>();
    final hang = Completer<LineAgeReport>();
    var starts = 0;
    cache.resetForTest(
      analyzeOverride: (repoPath, onProgress) {
        starts++;
        started.complete();
        return hang.future;
      },
    );

    final first = cache.analyzeOrCached(root.path);
    await started.future;
    final second = cache.analyzeOrCached(root.path);
    await Future<void>.delayed(Duration.zero);
    expect(starts, 1);
    cache.cancelAnalyze(root.path);

    await expectLater(first, throwsA(isA<LineAgeAnalysisCancelled>()));
    await expectLater(second, throwsA(isA<LineAgeAnalysisCancelled>()));

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
    final bothStarted = Completer<void>();
    final release = Completer<void>();
    final startedRoots = <String>[];
    cache.resetForTest(
      analyzeOverride: (repoPath, onProgress) async {
        startedRoots.add(repoPath);
        if (startedRoots.length == 2) bothStarted.complete();
        await release.future;
        return _report(totalLines: startedRoots.length);
      },
    );

    final first = cache.analyzeOrCached(firstRoot.path);
    final second = cache.analyzeOrCached(secondRoot.path);
    await bothStarted.future;
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
        measured: MeasuredLineAge(
          gitState: const ProjectSourceGitState(
            headCommit: 'abc123',
            headCommittedAt: null,
            uncommittedFileStamps: {'lib/a.dart': '15:1'},
          ),
          report: _report(totalLines: 314),
        ),
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
  File(path.join(root.path, 'lib', 'b.dart')).writeAsStringSync('class B {}\n');
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

/// Every file one line, last touched in 2001, so reused counts stand out.
LineAgeReport _reportAllIn2001(List<String> files) {
  return LineAgeReport(
    repoName: 'tmp',
    months: [
      LineAgeMonth(
        month: '2001-01',
        totalLines: files.length,
        segments: files.mapL(
          (file) => LineAgeSegment(file: file, lineCount: 1),
        ),
      ),
    ],
    totalLinesByFile: {for (final file in files) file: 1},
    totalLines: files.length,
    fileCount: files.length,
  );
}

List<String> _filesIn2001(LineAgeReport report) => [
  for (final month in report.months)
    if (month.month == '2001-01')
      for (final segment in month.segments) segment.file,
];
