import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Interprets `flutter run` / `flutter attach` log text.
abstract final class FlutterRunOutput {
  static final _vmServiceUriPattern = RegExp(
    r'(?:A Dart VM Service|The Dart VM service is available|'
    r'An Observatory debugger and profiler).*?(https?://\S+)',
    caseSensitive: false,
  );

  static bool looksReady(String text) {
    return text.contains('Flutter run key commands') ||
        text.contains('A Dart VM Service') ||
        text.contains('Flutter DevTools') ||
        text.contains('To hot restart') ||
        text.contains('Syncing files to device');
  }

  static String? vmServiceUriFrom(String text) {
    final match = _vmServiceUriPattern.firstMatch(text);
    if (match == null) return null;
    var uri = match.group(1)!;
    // Flutter sometimes trails the URL with punctuation.
    while (uri.endsWith('.') || uri.endsWith(')') || uri.endsWith(',')) {
      uri = uri.substring(0, uri.length - 1);
    }
    return uri;
  }
}

/// Deep process module for one `flutter run` / `flutter attach` (and pid teardown).
class MacosFlutterRun {
  MacosFlutterRun._(this._process)
      : pid = _process.pid,
        output = _mergeOutput(_process);

  final Process _process;

  final int pid;

  /// Merged stdout + stderr as text chunks.
  final Stream<String> output;

  static Future<MacosFlutterRun> start({required String projectPath}) async {
    final process = await Process.start(
      'flutter',
      const ['run', '-d', 'macos'],
      workingDirectory: projectPath,
      environment: _flutterEnvironment(),
      runInShell: false,
    );
    return MacosFlutterRun._(process);
  }

  /// Reattach hot-reload control to an already-running debug app.
  static Future<MacosFlutterRun> attach({
    required String projectPath,
    String? vmServiceUri,
  }) async {
    final arguments = <String>['attach', '-d', 'macos'];
    if (vmServiceUri != null && vmServiceUri.isNotEmpty) {
      arguments.addAll(['--debug-uri', vmServiceUri]);
    }
    final process = await Process.start(
      'flutter',
      arguments,
      workingDirectory: projectPath,
      environment: _flutterEnvironment(),
      runInShell: false,
    );
    return MacosFlutterRun._(process);
  }

  Future<void> sendKey(String key) async {
    _process.stdin.write('$key\n');
    await _process.stdin.flush();
  }

  /// Graceful quit: stdin `q`, then SIGTERM tree, then SIGKILL. Returns exit code.
  Future<int> quit() async {
    try {
      _process.stdin.write('q\n');
      await _process.stdin.flush();
    } catch (_) {
      // Process may already be closing / stdin detached.
    }
    try {
      return await _process.exitCode.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      await killPidTree(pid);
      try {
        return await _process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        Process.killPid(pid, ProcessSignal.sigkill);
        return await _process.exitCode;
      }
    }
  }

  Future<int> waitForExit() => _process.exitCode;

  static Future<bool> isPidAlive(int pid) async {
    if (pid <= 0) return false;
    final result = await Process.run('kill', ['-0', '$pid']);
    return result.exitCode == 0;
  }

  static Future<void> killPidTree(int pid) async {
    // Child macos app may outlive `flutter run` if we only signal the parent.
    await Process.run('pkill', ['-P', '$pid']);
    Process.killPid(pid, ProcessSignal.sigterm);
  }

  static Future<void> waitUntilPidExits(int pid) async {
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    while (DateTime.now().isBefore(deadline)) {
      if (!await isPidAlive(pid)) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    Process.killPid(pid, ProcessSignal.sigkill);
    await Process.run('pkill', ['-9', '-P', '$pid']);
  }

  static Stream<String> _mergeOutput(Process process) {
    return Stream<String>.multi((controller) {
      late final StreamSubscription<List<int>> stdoutSubscription;
      late final StreamSubscription<List<int>> stderrSubscription;

      void forward(List<int> bytes) {
        if (controller.isClosed) return;
        controller.add(utf8.decode(bytes, allowMalformed: true));
      }

      stdoutSubscription = process.stdout.listen(
        forward,
        onError: controller.addError,
      );
      stderrSubscription = process.stderr.listen(
        forward,
        onError: controller.addError,
      );

      controller.onCancel = () async {
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();
      };
    });
  }

  static Map<String, String> _flutterEnvironment() {
    final environment = Map<String, String>.from(Platform.environment);
    final path = environment['PATH'] ?? '';
    const brewBin = '/opt/homebrew/bin';
    const localBin = '/usr/local/bin';
    if (!path.contains(brewBin) || !path.contains(localBin)) {
      environment['PATH'] = '$brewBin:$localBin:$path';
    }
    return environment;
  }
}
