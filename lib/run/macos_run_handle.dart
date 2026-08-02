import 'dart:async';

import 'macos_flutter_run.dart';

/// OS-side binding for the active `flutter run` / `flutter attach` tools process.
///
/// Tracks the tools handle, the pid used for Stop (may predate attach), and the
/// VM service URI. Output/exit from a superseded generation are ignored.
class MacosRunHandle {
  MacosFlutterRun? _tools;
  StreamSubscription<String>? _outputSubscription;
  int? trackedPid;
  String? vmServiceUri;
  int _generation = 0;

  bool get hasLiveTools => _tools != null;
  MacosFlutterRun? get tools => _tools;
  int? get toolsPid => _tools?.pid;

  /// Invalidate in-flight output/exit watchers (e.g. workbench dispose).
  void invalidate() {
    _generation++;
  }

  Future<MacosFlutterRun> startNew(String projectPath) {
    return MacosFlutterRun.start(projectPath: projectPath);
  }

  Future<MacosFlutterRun> attachToRunning({
    required String projectPath,
    String? vmServiceUri,
  }) {
    return MacosFlutterRun.attach(
      projectPath: projectPath,
      vmServiceUri: vmServiceUri,
    );
  }

  /// Adopt [tools] as the live connection and listen until exit or [drop].
  void adopt(
    MacosFlutterRun tools, {
    required void Function(String chunk) onOutput,
    required void Function(int exitCode) onExit,
  }) {
    unawaited(_outputSubscription?.cancel());
    _tools = tools;
    trackedPid ??= tools.pid;
    final generation = ++_generation;
    _outputSubscription = tools.output.listen((chunk) {
      if (generation != _generation) return;
      onOutput(chunk);
    });
    unawaited(() async {
      final exitCode = await tools.waitForExit();
      if (generation != _generation) return;
      onExit(exitCode);
    }());
  }

  Future<void> sendKey(String key) async {
    final tools = _tools;
    if (tools == null) return;
    await tools.sendKey(key);
  }

  /// Quit live tools; if [trackedPid] is a different orphaned tools process, kill it too.
  Future<int> quit() async {
    final tools = _tools;
    final pid = trackedPid;
    if (tools == null) {
      if (pid != null) {
        await MacosFlutterRun.killPidTree(pid);
        await MacosFlutterRun.waitUntilPidExits(pid);
      }
      trackedPid = null;
      vmServiceUri = null;
      return 0;
    }

    final exitCode = await tools.quit();
    if (pid != null &&
        pid != tools.pid &&
        await MacosFlutterRun.isPidAlive(pid)) {
      await MacosFlutterRun.killPidTree(pid);
      await MacosFlutterRun.waitUntilPidExits(pid);
    }
    return exitCode;
  }

  /// Best-effort `d` detach so the app keeps running across workbench restart.
  Future<void> detachLeavingApp() async {
    final tools = _tools;
    _tools = null;
    await _outputSubscription?.cancel();
    _outputSubscription = null;
    if (tools == null) return;
    try {
      await tools.sendKey('d');
    } catch (_) {
      // Persistence still allows reclaim via VM service URI.
    }
  }

  /// Drop the Dart handle without signaling the OS process.
  Future<void> drop() async {
    _tools = null;
    await _outputSubscription?.cancel();
    _outputSubscription = null;
  }

  void clearIdentity() {
    trackedPid = null;
    vmServiceUri = null;
  }

  bool owns(MacosFlutterRun tools) => identical(_tools, tools);

  Future<void> releaseAfterExit(MacosFlutterRun tools) async {
    if (!identical(_tools, tools)) return;
    _tools = null;
    trackedPid = null;
    vmServiceUri = null;
    final outputSubscription = _outputSubscription;
    _outputSubscription = null;
    await outputSubscription?.cancel();
  }
}

/// Polls a pid until it dies (reattach-without-tools fallback).
class PidLivenessWatch {
  Timer? _timer;

  void watch(int pid, {required Future<void> Function() onDead}) {
    cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (await MacosFlutterRun.isPidAlive(pid)) return;
      cancel();
      await onDead();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
