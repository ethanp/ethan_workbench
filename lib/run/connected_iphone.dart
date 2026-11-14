import 'dart:convert';
import 'dart:io';

/// The physical iPhone `flutter devices` sees, over cable or Wi‑Fi.
abstract final class ConnectedIphone() {
  /// The phone's `flutter run -d` id. Throws when no phone is reachable.
  static Future<String> deviceId() async {
    final result = await Process.run('flutter', ['devices', '--machine']);
    if (result.exitCode != 0) {
      final stderrText = (result.stderr as String).trim();
      throw StateError(
        'flutter devices failed: '
        '${stderrText.isEmpty ? 'exit ${result.exitCode}' : stderrText}',
      );
    }
    final String? phoneId = iphoneIdFrom(result.stdout as String);
    if (phoneId != null) return phoneId;
    throw StateError(
      'No iPhone found. Connect it by cable or the same Wi‑Fi, unlock it, '
      'and keep Developer Mode on.',
    );
  }

  /// First physical iOS device in `flutter devices --machine` output, which
  /// may print status lines before the JSON list.
  static String? iphoneIdFrom(String devicesOutput) {
    final listStart = devicesOutput.indexOf('[');
    if (listStart < 0) return null;
    final devices = jsonDecode(devicesOutput.substring(listStart));
    if (devices is! List) return null;
    for (final device in devices) {
      if (device is! Map) continue;
      if (device['targetPlatform'] != 'ios') continue;
      if (device['emulator'] == true) continue;
      if (device['isSupported'] == false) continue;
      final id = device['id'];
      if (id is String && id.isNotEmpty) return id;
    }
    return null;
  }
}
