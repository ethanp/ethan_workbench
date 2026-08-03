import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'local_run_state.dart';

/// Mirrors the live local-run log for Cursor (and other tools) to read on disk.
///
/// Writes under:
/// - `{ethan_workbench}/.workbench/` when that package root can be resolved
/// - application support (always), as a fallback path
abstract final class LocalRunCursorMirror {
  static const logFileName = 'current_run.log';
  static const statusFileName = 'current_run_status.json';

  static final List<Directory> _mirrorDirectories = [];
  static Future<void>? _resolveFuture;
  static Timer? _statusDebounce;
  static LocalRunState? _pendingStatus;

  /// Resolve mirror directories once (workspace `.workbench` + app support).
  static Future<void> ensureResolved() {
    return _resolveFuture ??= _resolve();
  }

  static Future<void> _resolve() async {
    _mirrorDirectories.clear();

    final workspaceWorkbench = _resolveWorkspaceWorkbenchDir();
    if (workspaceWorkbench != null) {
      _mirrorDirectories.add(workspaceWorkbench);
    }

    try {
      final support = await getApplicationSupportDirectory();
      final supportWorkbench = Directory(path.join(support.path, 'cursor'));
      _mirrorDirectories.add(supportWorkbench);
    } catch (_) {
      // path_provider unavailable in some tests — workspace mirror only.
    }

    for (final directory in _mirrorDirectories) {
      await directory.create(recursive: true);
    }
  }

  static Directory? _resolveWorkspaceWorkbenchDir() {
    final fromEnv = Platform.environment['ETHAN_WORKBENCH_ROOT'];
    final packageRoots = <String>[
      if (fromEnv != null && fromEnv.isNotEmpty) fromEnv,
      Directory.current.path,
      if (Platform.environment['HOME'] case final home?
          when home.isNotEmpty)
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

  static Future<void> clearLog() async {
    await ensureResolved();
    for (final directory in _mirrorDirectories) {
      await _writeSafely(
        File(path.join(directory.path, logFileName)),
        '',
      );
    }
  }

  static Future<void> appendLog(String chunk) async {
    if (chunk.isEmpty) return;
    await ensureResolved();
    for (final directory in _mirrorDirectories) {
      await _writeSafely(
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
    await ensureResolved();
    final flutterException = state.flutterException;
    final payload = <String, Object?>{
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
        for (final directory in _mirrorDirectories) directory.path,
      ],
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);
    for (final directory in _mirrorDirectories) {
      await _writeSafely(
        File(path.join(directory.path, statusFileName)),
        encoded,
      );
    }
  }

  static Future<void> _writeSafely(
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
      // Mirror is best-effort — never fail the run session.
    }
  }
}
