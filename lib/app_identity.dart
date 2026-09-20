import 'dart:io';

import 'package:path/path.dart' as path;

/// Single source of truth for product / sync identity.
///
/// Folder name, Postgres role/DB, and compose stem must match [syncAppName].
/// See `RENAME.md` and the workspace `sync-app-identity` cursor rule.
abstract final class AppIdentity() {
  static const syncAppName = 'ethan_workbench';
  static const displayName = 'Ethan Workbench';

  /// Stable on-device PowerSync filename stem (survives product renames).
  static const localDatabaseStem = 'workbench';

  static const localDatabaseFileName = '${localDatabaseStem}_powersync.db';

  /// Same file the companion and daemon must share. Resolved without plugins
  /// so the headless daemon can open the ledger.
  static String get localDatabasePath {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('HOME is unset; cannot resolve the PowerSync path');
    }
    return path.join(home, 'Documents', localDatabaseFileName);
  }
}
