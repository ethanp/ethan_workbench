import 'dart:convert';
import 'dart:io';

import '../tooling/flutter_tool_environment.dart';
import 'deploy_platform.dart';

/// Runs `deploy.rb <ios|macos>` for a project and streams build output.
class DeployScriptRunner {
  /// When [exitCodePath] is set, wraps ruby in bash so the exit code (and a
  /// durable [logPath] tee) survive workbench hot restart when the Dart
  /// [Process] handle is lost.
  Future<int> runDeploy({
    required String deployRbPath,
    required String projectPath,
    required DeployPlatform platform,
    required bool force,
    required void Function(String chunk) onOutput,
    String? exitCodePath,
    String? logPath,
    void Function(int pid)? onStarted,
  }) async {
    final Process process;
    if (exitCodePath == null) {
      process = await Process.start(
        'ruby',
        [
          deployRbPath,
          platform.scriptArgument,
          if (force) '--force',
        ],
        workingDirectory: projectPath,
        environment: flutterToolEnvironment()..['PYTHONUNBUFFERED'] = '1',
        runInShell: false,
      );
    } else {
      final durableLog = logPath;
      if (durableLog != null) {
        await File(durableLog).writeAsString('');
      }
      process = await Process.start(
        '/bin/bash',
        [
          '-c',
          // $0/$1[/ $2] are deploy.rb args; EXIT_FILE / LOG_FILE survive restart.
          durableLog == null
              ? r'ruby "$0" "$1" ${2+"$2"}; ec=$?; printf %s "$ec" > "$EXIT_FILE"; exit $ec'
              : r'ruby "$0" "$1" ${2+"$2"} 2>&1 | tee -a "$LOG_FILE"; '
                    r'ec=${PIPESTATUS[0]}; printf %s "$ec" > "$EXIT_FILE"; exit $ec',
          deployRbPath,
          platform.scriptArgument,
          if (force) '--force',
        ],
        workingDirectory: projectPath,
        environment: {
          ...flutterToolEnvironment(),
          'PYTHONUNBUFFERED': '1',
          'EXIT_FILE': exitCodePath,
          'LOG_FILE': ?durableLog,
        },
        runInShell: false,
      );
    }

    onStarted?.call(process.pid);

    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .listen(onOutput);
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(onOutput);

    try {
      return await process.exitCode;
    } finally {
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
    }
  }
}
