import 'me_sim_iphone_simulator.dart';

/// Where a local `flutter run` should launch.
class const FlutterRunDevice._({
  /// Stable identity for UI / session matching (`macos`, `meSim`).
  required final String key,

  /// Short label for plates and status copy.
  required final String label,

  /// Argument for `flutter run -d` when [prepareDeviceId] is null.
  required final String flutterDeviceId,

  /// Boots / resolves the real device id (e.g. simulator UDID) before run.
  final Future<String> Function()? prepareDeviceId,
}) {
  static const macos = FlutterRunDevice._(
    key: 'macos',
    label: 'macOS',
    flutterDeviceId: 'macos',
  );

  static final meSim = FlutterRunDevice._(
    key: MeSimIphoneSimulator.simulatorName,
    label: MeSimIphoneSimulator.simulatorName,
    flutterDeviceId: MeSimIphoneSimulator.simulatorName,
    prepareDeviceId: MeSimIphoneSimulator.ensureBootedDeviceId,
  );

  static FlutterRunDevice? forKey(String key) {
    if (key == macos.key) return macos;
    if (key == meSim.key) return meSim;
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
