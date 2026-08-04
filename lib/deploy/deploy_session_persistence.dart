import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'deploy_job.dart';

/// On-disk snapshot of the active deploy + wait queue for Mac hot restart.
class DeploySessionRecord {
  const DeploySessionRecord({
    required this.activeJob,
    required this.projectPath,
    required this.exitCodePath,
    this.pid,
    this.waiting = const [],
  });

  final DeployJob activeJob;
  final String projectPath;
  final String exitCodePath;
  final int? pid;
  final List<DeployJob> waiting;

  Map<String, Object?> toJson() => {
    'activeJob': activeJob.toJson(),
    'projectPath': projectPath,
    'exitCodePath': exitCodePath,
    if (pid != null) 'pid': pid,
    'waiting': [for (final job in waiting) job.toJson()],
  };

  factory DeploySessionRecord.fromJson(Map<String, dynamic> json) {
    final waitingJson = json['waiting'] as List<dynamic>? ?? const [];
    return DeploySessionRecord(
      activeJob: DeployJob.fromJson(
        json['activeJob'] as Map<String, dynamic>,
      ),
      projectPath: json['projectPath'] as String,
      exitCodePath: json['exitCodePath'] as String,
      pid: json['pid'] as int?,
      waiting: [
        for (final item in waitingJson)
          DeployJob.fromJson(item as Map<String, dynamic>),
      ],
    );
  }
}

class DeploySessionPersistence {
  Future<Directory> _supportDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(supportDirectory.path);
  }

  Future<File> _sessionFile() async {
    final supportDirectory = await _supportDirectory();
    return File(path.join(supportDirectory.path, 'active_deploy_session.json'));
  }

  Future<String> exitCodePathFor(String jobId) async {
    final supportDirectory = await _supportDirectory();
    return path.join(supportDirectory.path, 'deploy_exit_$jobId.txt');
  }

  Future<DeploySessionRecord?> read() async {
    final file = await _sessionFile();
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return DeploySessionRecord.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(DeploySessionRecord record) async {
    final file = await _sessionFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(record.toJson()));
  }

  Future<void> clear({String? exitCodePath}) async {
    final file = await _sessionFile();
    if (await file.exists()) {
      await file.delete();
    }
    if (exitCodePath == null || exitCodePath.isEmpty) return;
    final exitFile = File(exitCodePath);
    if (await exitFile.exists()) {
      await exitFile.delete();
    }
  }
}
