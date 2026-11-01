import 'dart:io';

import 'package:ethan_sync/ethan_sync.dart';

import 'app_identity.dart';
import 'phone/phone_home.dart';
import 'server/macos_companion_screen.dart';
import 'sync/sync_config.dart';

void main() {
  SyncedAppLaunch(
    appName: AppIdentity.displayName,
    syncConfig: (_) => buildEthanWorkbenchSyncConfig(),
    syncRequired: false,
    home: Platform.isMacOS ? const MacosCompanionScreen() : const PhoneHome(),
  ).launch();
}
