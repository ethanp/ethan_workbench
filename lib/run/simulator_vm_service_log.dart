import 'dart:io';

import 'local_flutter_run.dart';

/// The VM service URL the simulator app printed, from the unified log.
///
/// `flutter attach --debug-url` forwards that device port. The host URL from
/// `flutter run` ("available at") is a different port and must not be reused.
class const SimulatorVmServiceLog() {
  Future<String?> latestListeningUri(String simulatorId) async {
    if (simulatorId.isEmpty || simulatorId == 'macos') return null;
    final result = await Process.run('xcrun', [
      'simctl',
      'spawn',
      simulatorId,
      'log',
      'show',
      '--last',
      '12h',
      '--style',
      'compact',
      '--predicate',
      'eventMessage CONTAINS "The Dart VM service is listening on"',
    ]);
    final stdoutText = result.stdout;
    if (stdoutText is! String || stdoutText.isEmpty) return null;
    return FlutterRunOutput.deviceVmServiceUriFrom(stdoutText);
  }
}
