import 'dart:io';

import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'agent/macos_companion_screen.dart';
import 'phone/phone_home.dart';
import 'sync/sync_config.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadAppDotEnv();

  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      if (phoneDeploySyncConfigured())
        syncConfigProvider.overrideWith(
          (ref) => buildPhoneDeploySyncConfig(preferences),
        ),
    ],
  );
  if (phoneDeploySyncConfigured()) {
    await SyncLifecycle.start(container);
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: PhoneDeployApp(container: container),
    ),
  );
}

class PhoneDeployApp extends StatelessWidget {
  const PhoneDeployApp({super.key, required this.container});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phone Deploy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: Platform.isMacOS
          ? MacosCompanionScreen(syncContainer: container)
          : const PhoneHome(),
    );
  }
}
