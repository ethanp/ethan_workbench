import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Shared on-disk mirror roots for Cursor (workspace `.workbench` + app support).
abstract final class WorkbenchCursorDirs {
  static final List<Directory> _directories = [];
  static Future<void>? _resolveFuture;

  static List<Directory> get directories => List.unmodifiable(_directories);

  static Future<void> ensureResolved() {
    return _resolveFuture ??= _resolve();
  }

  /// Test hook — resets cached resolution.
  static void resetForTest() {
    _resolveFuture = null;
    _directories.clear();
  }

  static Future<void> _resolve() async {
    _directories.clear();

    final workspaceWorkbench = _resolveWorkspaceWorkbenchDir();
    if (workspaceWorkbench != null) {
      _directories.add(workspaceWorkbench);
    }

    try {
      final support = await getApplicationSupportDirectory();
      _directories.add(Directory(path.join(support.path, 'cursor')));
    } catch (_) {
      // path_provider unavailable in some tests — workspace mirror only.
    }

    for (final directory in _directories) {
      await directory.create(recursive: true);
    }
  }

  static Directory? _resolveWorkspaceWorkbenchDir() {
    final fromEnv = Platform.environment['ETHAN_WORKBENCH_ROOT'];
    final packageRoots = <String>[
      if (fromEnv != null && fromEnv.isNotEmpty) fromEnv,
      Directory.current.path,
      if (Platform.environment['HOME'] case final home? when home.isNotEmpty)
        path.join(home, 'code/my-code/Active/Flutter/ethan_workbench'),
    ];

    for (final packageRoot in packageRoots) {
      final pubspec = File(path.join(packageRoot, 'pubspec.yaml'));
      if (!pubspec.existsSync()) continue;
      final pubspecText = pubspec.readAsStringSync();
      if (!pubspecText.contains('name: ethan_workbench')) continue;
      return Directory(path.join(packageRoot, '.workbench'));
    }
    return null;
  }

  static Future<void> writeSafely(
    File file,
    String contents, {
    bool append = false,
  }) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        contents,
        mode: append ? FileMode.append : FileMode.write,
        flush: true,
      );
    } catch (_) {
      // Mirror is best-effort — never fail the session.
    }
  }
}
