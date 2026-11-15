import 'dart:io';

import 'package:path/path.dart' as path;

/// A sync app's database (`Flutter/<app>/db/powersync.yaml`) and when its
/// newest nightly dump was made, as copied to this Mac by
/// `infra/backup/pull_database_dumps` into `~/Backups/postgres/<app>/`.
///
/// [lastBackupAt] is null when no dump of the database is on this Mac.
class const SyncDatabaseBackup({
  required final String databaseName,
  final DateTime? lastBackupAt,
}) {
  /// Matches the pull app's own "newest dump is old" notice.
  static const Duration staleAfter = Duration(days: 2);

  static final String pulledDumpsRoot = path.join(
    Platform.environment['HOME'] ?? '',
    'Backups',
    'postgres',
  );

  bool get isStale =>
      lastBackupAt == null ||
      DateTime.now().difference(lastBackupAt!) > staleAfter;

  /// Every project under a sync app's folder shares its database, so both
  /// `viant/apps/viant_ios` and `viant/apps/viant_macos` show `viant`.
  /// Null when the project is not part of a sync app.
  static Future<SyncDatabaseBackup?> findForProject({
    required String projectId,
    required String flutterRoot,
    required String macBackupsRoot,
  }) async {
    final String syncAppFolder = projectId.split('/').first;
    final powerSyncYaml = File(
      path.join(flutterRoot, syncAppFolder, 'db', 'powersync.yaml'),
    );
    if (!await powerSyncYaml.exists()) return null;
    return SyncDatabaseBackup(
      databaseName: syncAppFolder,
      lastBackupAt: await _newestDumpModifiedAt(
        Directory(path.join(macBackupsRoot, syncAppFolder)),
        databaseName: syncAppFolder,
      ),
    );
  }

  /// rsync keeps the server's mtime, so this is when the dump was written.
  static Future<DateTime?> _newestDumpModifiedAt(
    Directory dumpFolder, {
    required String databaseName,
  }) async {
    if (!await dumpFolder.exists()) return null;
    final dumpNamePattern = RegExp(
      '^${RegExp.escape(databaseName)}_\\d{4}-\\d{2}-\\d{2}\\.dump\$',
    );
    DateTime? newestModifiedAt;
    await for (final entity in dumpFolder.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!dumpNamePattern.hasMatch(path.basename(entity.path))) continue;
      final DateTime modifiedAt = await entity.lastModified();
      if (newestModifiedAt == null || modifiedAt.isAfter(newestModifiedAt)) {
        newestModifiedAt = modifiedAt;
      }
    }
    return newestModifiedAt;
  }

  factory fromJson(Map<String, dynamic> json) {
    final lastBackupAtJson = json['lastBackupAt'];
    return SyncDatabaseBackup(
      databaseName: json['databaseName'] as String,
      lastBackupAt: lastBackupAtJson is String
          ? DateTime.tryParse(lastBackupAtJson)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'databaseName': databaseName,
    if (lastBackupAt != null)
      'lastBackupAt': lastBackupAt!.toUtc().toIso8601String(),
  };
}
