/// Single source of truth for product / sync identity.
///
/// Folder name, Postgres role/DB, and compose stem must match [syncAppName].
/// See `RENAME.md` and the workspace `sync-app-identity` cursor rule.
abstract final class AppIdentity {
  static const syncAppName = 'ethan_workbench';
  static const displayName = 'Ethan Workbench';

  /// Stable on-device PowerSync filename stem (survives product renames).
  static const localDatabaseStem = 'workbench';
}
