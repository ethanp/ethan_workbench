import 'dart:convert';
import 'dart:io';

/// Boots and resolves the personal iPhone Simulator named [simulatorName].
abstract final class MeSimIphoneSimulator {
  static const simulatorName = 'meSim';

  /// Ensures meSim is Booted and returns its UDID for `flutter run -d`.
  static Future<String> ensureBootedDeviceId() async {
    final simulator = await _findMeSim();
    if (simulator == null) {
      throw StateError(
        'No iOS Simulator named "$simulatorName". '
        'Create one in Xcode → Window → Devices and Simulators.',
      );
    }

    if (simulator.state != 'Booted') {
      final boot = await Process.run('xcrun', [
        'simctl',
        'boot',
        simulator.udid,
      ]);
      // 149 = already booting/booted — fine to ignore.
      if (boot.exitCode != 0 && boot.exitCode != 149) {
        final stderr = (boot.stderr as String).trim();
        throw StateError(
          'Failed to boot $simulatorName: '
          '${stderr.isEmpty ? 'exit ${boot.exitCode}' : stderr}',
        );
      }
    }

    await Process.run('open', ['-a', 'Simulator']);
    return simulator.udid;
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

class _SimDevice {
  const _SimDevice({required this.udid, required this.state});

  final String udid;
  final String state;
}
