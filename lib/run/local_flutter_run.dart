import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'os_process_tree.dart';

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

/// One `flutter run` / `flutter attach` process (stdin, merged output, quit).
class LocalFlutterRun {
  LocalFlutterRun._(this._process)
    : pid = _process.pid,
      output = _mergeOutput(_process);

  final Process _process;

  final int pid;

  /// Merged stdout + stderr as text chunks.
  final Stream<String> output;

  static Future<LocalFlutterRun> start({
    required String projectPath,
    required String deviceId,
  }) async {
    final process = await Process.start(
      'flutter',
      ['run', '-d', deviceId],
      workingDirectory: projectPath,
      environment: _flutterEnvironment(),
      runInShell: false,
    );
    return LocalFlutterRun._(process);
  }

  /// Reattach hot-reload control to an already-running debug app.
  static Future<LocalFlutterRun> attach({
    required String projectPath,
    required String deviceId,
    String? vmServiceUri,
  }) async {
    final arguments = <String>['attach', '-d', deviceId];
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
    return LocalFlutterRun._(process);
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
      await killTreeTillExit();
      return await _process.exitCode;
    }
  }

  Future<int> waitForExit() => _process.exitCode;

  /// Signal this process tree and wait until it is gone.
  Future<void> killTreeTillExit() => pid.asOsProcessTree.killTillExit();

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
