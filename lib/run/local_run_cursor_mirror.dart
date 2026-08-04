import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../cursor/workbench_cursor_dirs.dart';
import 'local_run_state.dart';

/// Mirrors the live local-run log for Cursor (and other tools) to read on disk.
///
/// Writes under:
/// - `{ethan_workbench}/.workbench/` when that package root can be resolved
/// - application support (always), as a fallback path
abstract final class LocalRunCursorMirror {
  static const logFileName = 'current_run.log';
  static const statusFileName = 'current_run_status.json';

  static Timer? _statusDebounce;
  static LocalRunState? _pendingStatus;

  /// Resolve mirror directories once (workspace `.workbench` + app support).
  static Future<void> ensureResolved() => WorkbenchCursorDirs.ensureResolved();

  static Future<void> clearLog() async {
    await WorkbenchCursorDirs.ensureResolved();
    for (final directory in WorkbenchCursorDirs.directories) {
      await WorkbenchCursorDirs.writeSafely(
        File(path.join(directory.path, logFileName)),
        '',
      );
    }
  }

  static Future<void> appendLog(String chunk) async {
    if (chunk.isEmpty) return;
    await WorkbenchCursorDirs.ensureResolved();
    for (final directory in WorkbenchCursorDirs.directories) {
      await WorkbenchCursorDirs.writeSafely(
        File(path.join(directory.path, logFileName)),
        chunk,
        append: true,
      );
    }
  }

  /// Debounced status sidecar (no full log — see [logFileName]).
  static void scheduleStatus(LocalRunState state) {
    _pendingStatus = state;
    _statusDebounce?.cancel();
    _statusDebounce = Timer(const Duration(milliseconds: 150), () {
      final pending = _pendingStatus;
      if (pending == null) return;
      unawaited(writeStatus(pending));
    });
  }

  static Future<void> writeStatus(LocalRunState state) async {
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
      'logFile': logFileName,
      'logLength': state.log.length,
      if (flutterException != null)
        'flutterException': {
          'widget': flutterException.widget,
          'displayLocation': flutterException.displayLocation,
          'library': flutterException.library,
          'promptText': flutterException.promptText,
        },
      'mirrorDirectories': [
        for (final directory in WorkbenchCursorDirs.directories)
          directory.path,
      ],
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);
    for (final directory in WorkbenchCursorDirs.directories) {
      await WorkbenchCursorDirs.writeSafely(
        File(path.join(directory.path, statusFileName)),
        encoded,
      );
    }
  }
}
