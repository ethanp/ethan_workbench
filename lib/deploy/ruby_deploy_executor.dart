import 'dart:convert';
import 'dart:io';

import 'deploy_platform.dart';

/// Runs `deploy.rb <ios|macos>` for a project and streams build output.
class DeployScriptRunner {
  /// When [exitCodePath] is set, wraps ruby in bash so the exit code is written
  /// to disk — surviving workbench hot restart when the Dart [Process] handle
  /// is lost.
  Future<int> runDeploy({
    required String deployRbPath,
    required String projectPath,
    required DeployPlatform platform,
    required bool force,
    required void Function(String chunk) onOutput,
    String? exitCodePath,
    void Function(int pid)? onStarted,
  }) async {
    final process = exitCodePath == null
        ? await Process.start(
            'ruby',
            [
              deployRbPath,
              platform.scriptArgument,
              if (force) '--force',
            ],
            workingDirectory: projectPath,
            environment: {...Platform.environment, 'PYTHONUNBUFFERED': '1'},
            runInShell: false,
          )
        : await Process.start(
            '/bin/bash',
            [
              '-c',
              // $0/$1[/ $2] are deploy.rb args; EXIT_FILE survives isolate restart.
              r'ruby "$0" "$1" ${2+"$2"}; ec=$?; printf %s "$ec" > "$EXIT_FILE"; exit $ec',
              deployRbPath,
              platform.scriptArgument,
              if (force) '--force',
            ],
            workingDirectory: projectPath,
            environment: {
              ...Platform.environment,
              'PYTHONUNBUFFERED': '1',
              'EXIT_FILE': exitCodePath,
            },
            runInShell: false,
          );

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
