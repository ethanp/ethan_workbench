import 'package:ethan_workbench/run/me_sim_iphone_simulator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
