import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'line_age_analyzer.dart';
import 'line_age_report.dart';
import 'project_source_git_state.dart';

class const LineAgeCacheRecord({
  required final String gitRoot,
  required final MeasuredLineAge measured,
}) {
  Map<String, Object?> toJson() => {
    'gitRoot': gitRoot,
    'gitState': measured.gitState.toJson(),
    'report': measured.report.toJson(),
  };

  factory fromJson(Map<String, dynamic> json) {
    return LineAgeCacheRecord(
      gitRoot: json['gitRoot'] as String,
      measured: MeasuredLineAge(
        gitState: ProjectSourceGitState.fromJson(json['gitState']),
        report: LineAgeReport.fromJson(json['report'] as Map<String, dynamic>),
      ),
    );
  }
}

/// Disk store for line-age reports under application support.
class LineAgeCachePersistence({final Directory? _directoryOverride}) {
  Future<Directory> _directory() async {
    final override = _directoryOverride;
    if (override != null) return override;
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(path.join(supportDirectory.path, 'line_age_cache'));
  }

  Future<File> _fileFor(String gitRoot) async {
    final directory = await _directory();
    final digest = sha256.convert(utf8.encode(path.normalize(gitRoot)));
    return File(path.join(directory.path, '$digest.json'));
  }

  Future<Map<String, LineAgeCacheRecord>> readAll() async {
    final directory = await _directory();
    if (!await directory.exists()) return {};
    final records = <String, LineAgeCacheRecord>{};
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString());
        if (json is! Map<String, dynamic>) continue;
        final record = LineAgeCacheRecord.fromJson(json);
        records[path.normalize(record.gitRoot)] = record;
      } catch (_) {}
    }
    return records;
  }

  Future<void> write({
    required String gitRoot,
    required MeasuredLineAge measured,
  }) async {
    final normalizedRoot = path.normalize(gitRoot);
    final file = await _fileFor(normalizedRoot);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(
        LineAgeCacheRecord(
          gitRoot: normalizedRoot,
          measured: measured,
        ).toJson(),
      ),
    );
  }
}
