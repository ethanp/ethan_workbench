@Timeout.none
library;

import 'dart:io';

import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_workbench/cli/workbench_daemon_process.dart';
import 'package:flutter_test/flutter_test.dart';

/// Headless daemon: Flutter test binding without a window.
/// Not under test/ so `flutter test` does not hang the suite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _IoHttpOverrides();

  test('workbench daemon listens until SIGINT/SIGTERM', () async {
    await DotEnvSyncBootstrap.loadEnv();
    await WorkbenchDaemonProcess.runUntilSignal();
  });
}

/// TestWidgetsFlutterBinding otherwise stubs HTTP as 400.
class _IoHttpOverrides() extends HttpOverrides;
