import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'local_run_key.dart';

/// On-disk record of an active `flutter run` so workbench hot restart can reclaim it.
class const LocalRunRecord({
  required final int pid,
  required final String projectId,
  required final String projectName,
  required final String projectPath,
  required final bool readyForKeyCommands,
  required final String deviceKey,
  required final String deviceLabel,
  required final String flutterDeviceId,
  final String? vmServiceUri,
}) {
  LocalRunKey get runKey =>
      LocalRunKey(projectId: projectId, deviceKey: deviceKey);

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

  factory fromJson(Map<String, dynamic> json) {
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

class LocalRunPersistence() {
  Future<Directory> _directory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(path.join(supportDirectory.path, 'active_local_runs'));
  }

  Future<File> _fileFor(LocalRunKey runKey) async {
    final directory = await _directory();
    return File(path.join(directory.path, '${runKey.fileName}.json'));
  }

  Future<File> _legacyFile() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return File(path.join(supportDirectory.path, 'active_local_run.json'));
  }

  Future<void> migrateLegacyIfNeeded() async {
    final legacyFile = await _legacyFile();
    if (!await legacyFile.exists()) return;
    try {
      final json = jsonDecode(await legacyFile.readAsString());
      if (json is Map<String, dynamic>) {
        final record = LocalRunRecord.fromJson(json);
        await write(record.runKey, record);
      }
    } catch (_) {}
    if (await legacyFile.exists()) {
      await legacyFile.delete();
    }
  }

  Future<List<LocalRunRecord>> readAll() async {
    await migrateLegacyIfNeeded();
    final directory = await _directory();
    if (!await directory.exists()) return [];
    final records = <LocalRunRecord>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString());
        if (json is Map<String, dynamic>) {
          records.add(LocalRunRecord.fromJson(json));
        }
      } catch (_) {}
    }
    return records;
  }

  Future<LocalRunRecord?> read(LocalRunKey runKey) async {
    await migrateLegacyIfNeeded();
    final file = await _fileFor(runKey);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return LocalRunRecord.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(LocalRunKey runKey, LocalRunRecord record) async {
    final file = await _fileFor(runKey);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(record.toJson()));
  }

  Future<void> clear(LocalRunKey runKey) async {
    final file = await _fileFor(runKey);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
