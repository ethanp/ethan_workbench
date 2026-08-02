import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'paired_session.dart';

/// Disk-backed paired phone sessions for the Mac companion (token hashes only).
class PairedSessionStore {
  PairedSessionStore({this._directory});

  final Directory? _directory;

  static const _fileName = 'paired_phone_sessions.json';

  Future<File> _file() async {
    final directory =
        _directory ?? await getApplicationSupportDirectory();
    return File(path.join(directory.path, _fileName));
  }

  Future<List<PairedSession>> readSessions() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return const [];
      final sessionMaps = decoded['sessions'] as List<dynamic>? ?? const [];
      return [
        for (final sessionMap in sessionMaps)
          if (sessionMap is Map<String, dynamic>)
            PairedSession.fromJson(sessionMap),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> writeSessions(List<PairedSession> sessions) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'sessions': [
            for (final session in sessions) session.toJson(),
          ],
        }),
      );
      if (Platform.isMacOS || Platform.isLinux) {
        await Process.run('chmod', ['600', file.path]);
      }
    } catch (_) {
      // No path_provider binding (unit smoke tests) or disk error — memory
      // sessions still work until the next successful persist.
    }
  }
}
