import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'powersync_schema.dart';

const _log = ELogger('PhoneDeploySync');

bool phoneDeploySyncConfigured() => DotEnvSyncBootstrap.isConfigured();

/// Builds phone_deploy's [SyncConfig] for `ethan_sync`.
SyncConfig buildPhoneDeploySyncConfig(SharedPreferences preferences) {
  return DotEnvSyncBootstrap.build(
    preferences: preferences,
    appName: 'phone_deploy',
    powersyncPort: 8084,
    postgrestPort: 3007,
    schema: phoneDeploySchema,
    upload: UploadSettings(
      strategy: CoalescingBatchUploadStrategy(),
      conflictColumns: const {
        'deploy_state': 'project_id,platform',
      },
    ),
    onSyncError: (message) => _log.warn(message),
  );
}
