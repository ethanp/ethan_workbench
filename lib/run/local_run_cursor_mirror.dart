import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../cursor/workbench_cursor_dirs.dart';
import 'local_run_key.dart';
import 'local_run_state.dart';

/// Mirrors live local-run logs for Cursor (and other tools) to read on disk.
///
/// Writes under `{ethan_workbench}/.workbench/local_runs/` and the application
/// support `cursor/local_runs/` fallback.
abstract final class LocalRunCursorMirror {
  static final Map<LocalRunKey, Timer> _statusDebounce = {};
  static final Map<LocalRunKey, LocalRunState> _pendingStatus = {};

  static String logRelativePath(LocalRunKey runKey) =>
      path.join('local_runs', '${runKey.fileName}.log');

  static String statusRelativePath(LocalRunKey runKey) =>
      path.join('local_runs', '${runKey.fileName}_status.json');

  /// Resolve mirror directories once (workspace `.workbench` + app support).
  static Future<void> ensureResolved() => WorkbenchCursorDirs.ensureResolved();

  static Future<void> clearLog(LocalRunKey runKey) async {
    await WorkbenchCursorDirs.ensureResolved();
    for (final directory in WorkbenchCursorDirs.directories) {
      await WorkbenchCursorDirs.writeSafely(
        File(path.join(directory.path, logRelativePath(runKey))),
        '',
      );
    }
  }

  static Future<void> appendLog(LocalRunKey runKey, String chunk) async {
    if (chunk.isEmpty) return;
    await WorkbenchCursorDirs.ensureResolved();
    for (final directory in WorkbenchCursorDirs.directories) {
      await WorkbenchCursorDirs.writeSafely(
        File(path.join(directory.path, logRelativePath(runKey))),
        chunk,
        append: true,
      );
    }
  }

  /// Debounced status sidecar (no full log — see [logRelativePath]).
  static void scheduleStatus(LocalRunKey runKey, LocalRunState state) {
    _pendingStatus[runKey] = state;
    _statusDebounce[runKey]?.cancel();
    _statusDebounce[runKey] = Timer(const Duration(milliseconds: 150), () {
      final pending = _pendingStatus.remove(runKey);
      _statusDebounce.remove(runKey);
      if (pending == null) return;
      unawaited(writeStatus(runKey, pending));
    });
  }

  static Future<void> writeStatus(
    LocalRunKey runKey,
    LocalRunState state,
  ) async {
    await WorkbenchCursorDirs.ensureResolved();
    final flutterException = state.flutterException;
    final payload = <String, Object?>{
      'kind': 'local_run',
      'updatedAt': DateTime.now().toIso8601String(),
      'status': state.status.name,
      'projectId': state.projectId,
      'projectName': state.projectName,
      'projectPath': state.projectPath,
      'deviceKey': state.deviceKey,
      'deviceLabel': state.deviceLabel,
      'readyForKeyCommands': state.readyForKeyCommands,
      'errorMessage': state.errorMessage,
      'exitCode': state.exitCode,
      'logFile': logRelativePath(runKey),
      'logLength': state.log.length,
      if (flutterException != null)
        'flutterException': {
          'widget': flutterException.widget,
          'displayLocation': flutterException.displayLocation,
          'library': flutterException.library,
          'promptText': flutterException.promptText,
        },
      'mirrorDirectories': [
        for (final directory in WorkbenchCursorDirs.directories) directory.path,
      ],
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);
    for (final directory in WorkbenchCursorDirs.directories) {
      await WorkbenchCursorDirs.writeSafely(
        File(path.join(directory.path, statusRelativePath(runKey))),
        encoded,
      );
    }
  }
}
