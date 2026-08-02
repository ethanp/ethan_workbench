import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// On-disk record of an active `flutter run` so workbench hot restart can reclaim it.
class LocalRunRecord {
  const LocalRunRecord({
    required this.pid,
    required this.projectId,
    required this.projectName,
    required this.projectPath,
    required this.readyForKeyCommands,
    required this.deviceKey,
    required this.deviceLabel,
    required this.flutterDeviceId,
    this.vmServiceUri,
  });

  final int pid;
  final String projectId;
  final String projectName;
  final String projectPath;
  final bool readyForKeyCommands;
  final String deviceKey;
  final String deviceLabel;
  final String flutterDeviceId;
  final String? vmServiceUri;

  Map<String, Object?> toJson() => {
    'pid': pid,
    'projectId': projectId,
    'projectName': projectName,
    'projectPath': projectPath,
    'readyForKeyCommands': readyForKeyCommands,
    'deviceKey': deviceKey,
    'deviceLabel': deviceLabel,
    'flutterDeviceId': flutterDeviceId,
    if (vmServiceUri != null) 'vmServiceUri': vmServiceUri,
  };

  factory LocalRunRecord.fromJson(Map<String, dynamic> json) {
    return LocalRunRecord(
      pid: json['pid'] as int,
      projectId: json['projectId'] as String,
      projectName: json['projectName'] as String,
      projectPath: json['projectPath'] as String,
      readyForKeyCommands: json['readyForKeyCommands'] as bool? ?? false,
      deviceKey: json['deviceKey'] as String? ?? 'macos',
      deviceLabel: json['deviceLabel'] as String? ?? 'macOS',
      flutterDeviceId: json['flutterDeviceId'] as String? ?? 'macos',
      vmServiceUri: json['vmServiceUri'] as String?,
    );
  }
}

class LocalRunPersistence {
  Future<File> _file() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return File(path.join(supportDirectory.path, 'active_local_run.json'));
  }

  Future<LocalRunRecord?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return LocalRunRecord.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(LocalRunRecord record) async {
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
