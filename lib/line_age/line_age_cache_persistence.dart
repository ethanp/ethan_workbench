import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'line_age_analyzer.dart';

class LineAgeCacheRecord {
  const LineAgeCacheRecord({
    required this.gitRoot,
    required this.fingerprint,
    required this.report,
  });

  final String gitRoot;
  final String fingerprint;
  final LineAgeReport report;

  Map<String, Object?> toJson() => {
    'gitRoot': gitRoot,
    'fingerprint': fingerprint,
    'report': report.toJson(),
  };

  factory LineAgeCacheRecord.fromJson(Map<String, dynamic> json) {
    return LineAgeCacheRecord(
      gitRoot: json['gitRoot'] as String,
      fingerprint: json['fingerprint'] as String,
      report: LineAgeReport.fromJson(json['report'] as Map<String, dynamic>),
    );
  }
}

/// Disk store for line-age reports under application support.
class LineAgeCachePersistence {
  LineAgeCachePersistence({Directory? directory}) : _directoryOverride = directory;

  final Directory? _directoryOverride;

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
    required String fingerprint,
    required LineAgeReport report,
  }) async {
    final normalizedRoot = path.normalize(gitRoot);
    final file = await _fileFor(normalizedRoot);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(
        LineAgeCacheRecord(
          gitRoot: normalizedRoot,
          fingerprint: fingerprint,
          report: report,
        ).toJson(),
      ),
    );
  }
}
