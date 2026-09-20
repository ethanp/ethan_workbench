@Timeout.none
library;

import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:ethan_workbench/cli/workbench_daemon_process.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

/// Headless daemon: Flutter test binding without a window.
/// Not under test/ so `flutter test` does not hang the suite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _IoHttpOverrides();

  test('workbench daemon listens until SIGINT/SIGTERM', () async {
    await loadAppDotEnv();
    final envFile = File(path.join(Directory.current.path, '.env'));
    if (envFile.existsSync()) {
      dotenv.loadFromString(envString: envFile.readAsStringSync());
    }
    await WorkbenchDaemonProcess.runUntilSignal();
  });
}

/// TestWidgetsFlutterBinding otherwise stubs HTTP as 400.
class _IoHttpOverrides() extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return HttpClient(context: context);
  }
}
