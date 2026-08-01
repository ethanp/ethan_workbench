import 'dart:convert';
import 'dart:io';

import 'deploy_platform.dart';

/// Runs `deploy.rb <ios|macos>` for a project and streams build output.
class DeployScriptRunner {
  Future<int> runDeploy({
    required String deployRbPath,
    required String projectPath,
    required DeployPlatform platform,
    required bool force,
    required void Function(String chunk) onOutput,
  }) async {
    final arguments = [deployRbPath, platform.scriptArgument];
    if (force) arguments.add('--force');

    final process = await Process.start(
      'ruby',
      arguments,
      workingDirectory: projectPath,
      environment: {
        ...Platform.environment,
        'PYTHONUNBUFFERED': '1',
      },
      runInShell: false,
    );

    final stdoutSubscription =
        process.stdout.transform(utf8.decoder).listen(onOutput);
    final stderrSubscription =
        process.stderr.transform(utf8.decoder).listen(onOutput);

    try {
      return await process.exitCode;
    } finally {
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
    }
  }
}
