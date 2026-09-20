import 'dart:convert';
import 'dart:io';

import 'package:ethan_workbench/run/me_sim_iphone_simulator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('meSim simulator exists in simctl inventory', () async {
    final result = await Process.run('xcrun', [
      'simctl',
      'list',
      'devices',
      'available',
      '-j',
    ]);
    expect(result.exitCode, 0);
    final payload = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final devicesByRuntime =
        payload['devices'] as Map<String, dynamic>? ?? const {};
    var found = false;
    for (final runtimeDevices in devicesByRuntime.values) {
      if (runtimeDevices is! List) continue;
      for (final entry in runtimeDevices) {
        if (entry is! Map) continue;
        if (entry['name'] == MeSimIphoneSimulator.simulatorName) {
          found = true;
          expect(entry['udid'], isNotEmpty);
        }
      }
    }
    expect(
      found,
      isTrue,
      reason: 'Create an iOS Simulator named meSim for local runs',
    );
  });

  test('Xcode 27 Device Hub is preferred over legacy Simulator.app', () {
    expect(
      MeSimIphoneSimulator.simulatorWindowAppCandidates(
        '/Applications/Xcode.app/Contents/Developer',
      ),
      [
        '/Applications/Xcode.app/Contents/Applications/DeviceHub.app',
        '/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app',
      ],
    );
  });

  test('this Mac has Device Hub or Simulator.app', () async {
    final result = await Process.run('xcode-select', ['-p']);
    expect(result.exitCode, 0);
    final developerDir = (result.stdout as String).trim();
    final existing = MeSimIphoneSimulator.simulatorWindowAppCandidates(
      developerDir,
    ).where((appPath) => Directory(appPath).existsSync());
    expect(
      existing,
      isNotEmpty,
      reason: 'Xcode must ship Device Hub (27+) or Simulator.app',
    );
  });
}
