import 'dart:io';

import 'package:ethan_workbench/cursor/workbench_cursor_dirs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory fakePackageRoot;
  late Directory originalWorkingDirectory;

  setUp(() async {
    originalWorkingDirectory = Directory.current;
    fakePackageRoot = await Directory.systemTemp.createTemp('cursor_mirror_');
    File(
      path.join(fakePackageRoot.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: ethan_workbench\n');
    Directory.current = fakePackageRoot;
    WorkbenchCursorDirs.resetForTest();
  });

  tearDown(() async {
    Directory.current = originalWorkingDirectory;
    WorkbenchCursorDirs.resetForTest();
    if (await fakePackageRoot.exists()) {
      await fakePackageRoot.delete(recursive: true);
    }
  });

  test('concurrent unawaited log appends keep every chunk in order', () async {
    await WorkbenchCursorDirs.ensureResolved();
    final logFile = File(
      path.join(WorkbenchCursorDirs.directories.first.path, 'deploy.log'),
    );

    final chunks = [for (var index = 0; index < 200; index++) 'chunk $index\n'];
    await Future.wait([
      for (final chunk in chunks)
        WorkbenchCursorDirs.writeSafely(logFile, chunk, append: true),
    ]);

    expect(await logFile.readAsString(), chunks.join());
  });

  test('truncate queued behind pending appends wins', () async {
    await WorkbenchCursorDirs.ensureResolved();
    final logFile = File(
      path.join(WorkbenchCursorDirs.directories.first.path, 'deploy.log'),
    );

    final unawaitedAppend = WorkbenchCursorDirs.writeSafely(
      logFile,
      'stale run output\n',
      append: true,
    );
    await WorkbenchCursorDirs.writeSafely(logFile, '');
    await unawaitedAppend;

    expect(await logFile.readAsString(), isEmpty);
  });
}
