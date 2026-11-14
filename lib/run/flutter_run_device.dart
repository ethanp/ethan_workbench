import 'connected_iphone.dart';
import 'me_sim_iphone_simulator.dart';

/// Where a local `flutter run` should launch.
class const FlutterRunDevice._({
  /// Stable identity for UI / session matching (`macos`, `meSim`, `iphone`).
  required final String key,

  /// Short label for plates and status copy.
  required final String label,

  /// What the Run cell says while nothing runs (`Debug`, `Simulator`).
  required final String runCaption,

  /// The Run cell's word when the cluster is too narrow for a caption.
  required final String condensedRunLabel,

  /// Argument for `flutter run -d` when [prepareDeviceId] is null.
  required final String flutterDeviceId,

  /// The app's VM service lives on another device: `flutter run` prints a
  /// host forward, and reattach must pass the device's own URI.
  final bool vmServiceIsForwarded = false,

  /// Boots / resolves the real device id (e.g. simulator UDID) before run.
  final Future<String> Function()? prepareDeviceId,
}) {
  static const macos = FlutterRunDevice._(
    key: 'macos',
    label: 'macOS',
    runCaption: 'Debug',
    condensedRunLabel: 'Run',
    flutterDeviceId: 'macos',
  );

  static final meSim = FlutterRunDevice._(
    key: MeSimIphoneSimulator.simulatorName,
    label: MeSimIphoneSimulator.simulatorName,
    runCaption: 'Simulator',
    condensedRunLabel: 'Sim',
    flutterDeviceId: MeSimIphoneSimulator.simulatorName,
    vmServiceIsForwarded: true,
    prepareDeviceId: MeSimIphoneSimulator.ensureBootedDeviceId,
  );

  static final iphone = FlutterRunDevice._(
    key: 'iphone',
    label: 'iPhone',
    runCaption: 'iPhone',
    condensedRunLabel: 'iPhone',
    flutterDeviceId: 'iphone',
    vmServiceIsForwarded: true,
    prepareDeviceId: ConnectedIphone.deviceId,
  );

  static final all = [macos, meSim, iphone];

  static FlutterRunDevice? forKey(String key) {
    for (final device in all) {
      if (device.key == key) return device;
    }
    return null;
  }

  Future<String> resolveFlutterDeviceId() async {
    final prepare = prepareDeviceId;
    if (prepare != null) return prepare();
    return flutterDeviceId;
  }

  @override
  bool operator ==(Object other) =>
      other is FlutterRunDevice && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
