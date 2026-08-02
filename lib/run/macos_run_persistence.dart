import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// On-disk record of an active `flutter run` so workbench hot restart can reclaim it.
class MacosRunRecord {
  const MacosRunRecord({
    required this.pid,
    required this.projectId,
    required this.projectName,
    required this.projectPath,
    required this.readyForKeyCommands,
    this.vmServiceUri,
  });

  final int pid;
  final String projectId;
  final String projectName;
  final String projectPath;
  final bool readyForKeyCommands;
  final String? vmServiceUri;

  Map<String, Object?> toJson() => {
    'pid': pid,
    'projectId': projectId,
    'projectName': projectName,
    'projectPath': projectPath,
    'readyForKeyCommands': readyForKeyCommands,
    if (vmServiceUri != null) 'vmServiceUri': vmServiceUri,
  };

  factory MacosRunRecord.fromJson(Map<String, dynamic> json) {
    return MacosRunRecord(
      pid: json['pid'] as int,
      projectId: json['projectId'] as String,
      projectName: json['projectName'] as String,
      projectPath: json['projectPath'] as String,
      readyForKeyCommands: json['readyForKeyCommands'] as bool? ?? false,
      vmServiceUri: json['vmServiceUri'] as String?,
    );
  }
}

class MacosRunPersistence {
  Future<File> _file() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return File(path.join(supportDirectory.path, 'active_macos_run.json'));
  }

  Future<MacosRunRecord?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return MacosRunRecord.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(MacosRunRecord record) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(record.toJson()));
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }
}
