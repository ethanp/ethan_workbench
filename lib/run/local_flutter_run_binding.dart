import 'dart:async';

import 'local_flutter_run.dart';
import 'os_process_tree.dart';

/// OS-side binding for the active `flutter run` / `flutter attach` process.
///
/// Tracks that process, the pid used for Stop (may predate attach), and the
/// VM service URI. Output/exit from a superseded generation are ignored.
class LocalFlutterRunBinding {
  LocalFlutterRun? _flutterRun;
  StreamSubscription<String>? _outputSubscription;
  int? trackedPid;
  String? vmServiceUri;
  int _generation = 0;

  bool get hasFlutterRun => _flutterRun != null;
  LocalFlutterRun? get flutterRun => _flutterRun;
  int? get flutterRunPid => _flutterRun?.pid;

  /// Invalidate in-flight output/exit watchers (e.g. workbench dispose).
  void invalidate() {
    _generation++;
  }

  Future<LocalFlutterRun> startNew({
    required String projectPath,
    required String deviceId,
  }) {
    return LocalFlutterRun.start(
      projectPath: projectPath,
      deviceId: deviceId,
    );
  }

  Future<LocalFlutterRun> attachToRunning({
    required String projectPath,
    required String deviceId,
    String? vmServiceUri,
  }) {
    return LocalFlutterRun.attach(
      projectPath: projectPath,
      deviceId: deviceId,
      vmServiceUri: vmServiceUri,
    );
  }

  /// Adopt [flutterRun] as the live connection and listen until exit or [drop].
  void adopt(
    LocalFlutterRun flutterRun, {
    required void Function(String chunk) onOutput,
    required void Function(int exitCode) onExit,
  }) {
    unawaited(_outputSubscription?.cancel());
    _flutterRun = flutterRun;
    trackedPid ??= flutterRun.pid;
    final generation = ++_generation;
    _outputSubscription = flutterRun.output.listen((chunk) {
      if (generation != _generation) return;
      onOutput(chunk);
    });
    unawaited(() async {
      final exitCode = await flutterRun.waitForExit();
      if (generation != _generation) return;
      onExit(exitCode);
    }());
  }

  Future<void> sendKey(String key) async {
    final flutterRun = _flutterRun;
    if (flutterRun == null) return;
    await flutterRun.sendKey(key);
  }

  /// Quit the live process; if [trackedPid] is a different orphan, kill it too.
  Future<int> quit() async {
    final flutterRun = _flutterRun;
    final pid = trackedPid;
    if (flutterRun == null) {
      if (pid != null) {
        await pid.asOsProcessTree.killTillExit();
      }
      trackedPid = null;
      vmServiceUri = null;
      return 0;
    }

    final exitCode = await flutterRun.quit();
    if (pid != null && pid != flutterRun.pid) {
      await pid.asOsProcessTree.killTillExit();
    }
    return exitCode;
  }

  /// Best-effort `d` detach so the app keeps running across workbench restart.
  Future<void> detachLeavingApp() async {
    final flutterRun = _flutterRun;
    _flutterRun = null;
    await _outputSubscription?.cancel();
    _outputSubscription = null;
    if (flutterRun == null) return;
    try {
      await flutterRun.sendKey('d');
    } catch (_) {
      // Persistence still allows reclaim via VM service URI.
    }
  }

  /// Drop the Dart reference without signaling the OS process.
  Future<void> drop() async {
    _flutterRun = null;
    await _outputSubscription?.cancel();
    _outputSubscription = null;
  }

  void clearIdentity() {
    trackedPid = null;
    vmServiceUri = null;
  }

  bool owns(LocalFlutterRun flutterRun) => identical(_flutterRun, flutterRun);

  Future<void> releaseAfterExit(LocalFlutterRun flutterRun) async {
    if (!identical(_flutterRun, flutterRun)) return;
    _flutterRun = null;
    trackedPid = null;
    vmServiceUri = null;
    final outputSubscription = _outputSubscription;
    _outputSubscription = null;
    await outputSubscription?.cancel();
  }
}

