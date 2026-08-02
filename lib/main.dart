import 'dart:io';

import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'agent/macos_companion_screen.dart';
import 'app_identity.dart';
import 'phone/phone_home.dart';
import 'sync/sync_config.dart';
import 'package:ethan_ui/ethan_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadAppDotEnv();

  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      if (ethanWorkbenchSyncConfigured())
        syncConfigProvider.overrideWith(
          (ref) => buildEthanWorkbenchSyncConfig(preferences),
        ),
    ],
  );
  if (ethanWorkbenchSyncConfigured()) {
    await SyncLifecycle.start(container);
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: EthanWorkbenchApp(container: container),
    ),
  );
}

class EthanWorkbenchApp extends StatelessWidget {
  const EthanWorkbenchApp({required this.container});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppIdentity.displayName,
      debugShowCheckedModeBanner: false,
      theme: ETheme.build(),
      home: Platform.isMacOS
          ? MacosCompanionScreen(syncContainer: container)
          : const PhoneHome(),
    );
  }
}
