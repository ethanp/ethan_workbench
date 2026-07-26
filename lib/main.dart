import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import 'agent/macos_companion_screen.dart';
import 'phone/phone_home.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadAppDotEnv();
  runApp(const PhoneDeployApp());
}

class PhoneDeployApp extends StatelessWidget {
  const PhoneDeployApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phone Deploy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: Platform.isMacOS
          ? const MacosCompanionScreen()
          : const PhoneHome(),
    );
  }
}
