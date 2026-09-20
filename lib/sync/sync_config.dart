import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';

import '../app_identity.dart';
import 'powersync_schema.dart';

const _log = ELogger('EthanWorkbenchSync');

bool ethanWorkbenchSyncConfigured() => DotEnvSyncBootstrap.isConfigured();

/// Builds ethan_workbench's [SyncConfig] for `ethan_sync`.
///
/// Database path is [AppIdentity.localDatabasePath] so the daemon (no
/// SharedPreferences plugin) and the companion open the same ledger file.
SyncConfig buildEthanWorkbenchSyncConfig() {
  return DotEnvSyncBootstrap.build(
    databasePath: () async => AppIdentity.localDatabasePath,
    appName: AppIdentity.syncAppName,
    localDatabaseStem: AppIdentity.localDatabaseStem,
    powersyncPort: 8084,
    postgrestPort: 3007,
    schema: ethanWorkbenchSchema,
    upload: UploadSettings(
      strategy: CoalescingBatchUploadStrategy(),
      conflictColumns: const {'deploy_state': 'project_id,platform'},
    ),
    onSyncError: _log.warn,
  );
}
