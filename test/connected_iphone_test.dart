import 'package:ethan_workbench/run/connected_iphone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('picks the physical iPhone over the simulator and the Mac', () {
    const devicesOutput = '''
Checking for wireless devices...
[
  {"name": "meSim", "id": "SIM-UDID", "targetPlatform": "ios", "emulator": true, "isSupported": true},
  {"name": "macOS", "id": "macos", "targetPlatform": "darwin", "emulator": false, "isSupported": true},
  {"name": "Ethan's iPhone", "id": "00008140-PHONE", "targetPlatform": "ios", "emulator": false, "isSupported": true}
]
''';
    expect(ConnectedIphone.iphoneIdFrom(devicesOutput), '00008140-PHONE');
  });

  test('no physical iPhone means no id', () {
    const devicesOutput =
        '[{"name": "meSim", "id": "SIM-UDID", "targetPlatform": "ios", "emulator": true}]';
    expect(ConnectedIphone.iphoneIdFrom(devicesOutput), isNull);
  });
}
