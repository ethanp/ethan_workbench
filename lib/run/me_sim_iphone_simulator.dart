import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Boots and resolves the personal iPhone Simulator named [simulatorName].
abstract final class MeSimIphoneSimulator() {
  static const simulatorName = 'meSim';

  /// Xcode 27 paints the device in Device Hub; older Xcode uses Simulator.app.
  static List<String> simulatorWindowAppCandidates(String developerDir) {
    final xcodeContents = p.dirname(developerDir);
    return [
      p.join(xcodeContents, 'Applications', 'DeviceHub.app'),
      p.join(developerDir, 'Applications', 'Simulator.app'),
    ];
  }

  /// Ensures meSim is Booted, shows its window, and returns its UDID.
  static Future<String> ensureBootedDeviceId() async {
    final simulator = await _findMeSim();
    if (simulator == null) {
      throw StateError(
        'No iOS Simulator named "$simulatorName". '
        'Create one in Xcode → Window → Devices and Simulators.',
      );
    }

    if (simulator.state != 'Booted') {
      await _boot(simulator.udid);
    }
    await _openSimulatorWindow(udid: simulator.udid);
    return simulator.udid;
  }

  static Future<void> _boot(String udid) async {
    final boot = await Process.run('xcrun', ['simctl', 'boot', udid]);
    // 149 = already booting/booted — fine to ignore.
    if (boot.exitCode != 0 && boot.exitCode != 149) {
      final stderr = (boot.stderr as String).trim();
      throw StateError(
        'Failed to boot $simulatorName: '
        '${stderr.isEmpty ? 'exit ${boot.exitCode}' : stderr}',
      );
    }
  }

  static Future<void> _openSimulatorWindow({required String udid}) async {
    final appPath = await _simulatorWindowAppPath();
    final opened = await Process.run('open', [
      '-a',
      appPath,
      '--args',
      '-CurrentDeviceUDID',
      udid,
    ]);
    if (opened.exitCode != 0) {
      final stderr = (opened.stderr as String).trim();
      throw StateError(
        'Failed to open the simulator window ($appPath): '
        '${stderr.isEmpty ? 'exit ${opened.exitCode}' : stderr}',
      );
    }
  }

  static Future<String> _simulatorWindowAppPath() async {
    final developerDir = await _xcodeDeveloperDir();
    for (final appPath in simulatorWindowAppCandidates(developerDir)) {
      if (await Directory(appPath).exists()) return appPath;
    }
    throw StateError(
      'Xcode has no Device Hub or Simulator app to show $simulatorName.',
    );
  }

  static Future<String> _xcodeDeveloperDir() async {
    final result = await Process.run('xcode-select', ['-p']);
    if (result.exitCode != 0) {
      final stderr = (result.stderr as String).trim();
      throw StateError(
        'xcode-select -p failed: '
        '${stderr.isEmpty ? 'exit ${result.exitCode}' : stderr}',
      );
    }
    return (result.stdout as String).trim();
  }

  static Future<_SimDevice?> _findMeSim() async {
    final result = await Process.run('xcrun', [
      'simctl',
      'list',
      'devices',
      'available',
      '-j',
    ]);
    if (result.exitCode != 0) {
      final stderr = (result.stderr as String).trim();
      throw StateError(
        'simctl list failed: ${stderr.isEmpty ? result.exitCode : stderr}',
      );
    }

    final payload = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final devicesByRuntime =
        payload['devices'] as Map<String, dynamic>? ?? const {};
    for (final runtimeDevices in devicesByRuntime.values) {
      if (runtimeDevices is! List) continue;
      for (final entry in runtimeDevices) {
        if (entry is! Map) continue;
        final name = entry['name'] as String?;
        if (name != simulatorName) continue;
        final udid = entry['udid'] as String?;
        final state = entry['state'] as String?;
        final isAvailable = entry['isAvailable'] as bool? ?? true;
        if (udid == null || udid.isEmpty || !isAvailable) continue;
        return _SimDevice(udid: udid, state: state ?? 'Shutdown');
      }
    }
    return null;
  }
}

class const _SimDevice({
  required final String udid,
  required final String state,
});
