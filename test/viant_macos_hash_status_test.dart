import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phone_deploy/deploy/deploy_platform.dart';
import 'package:phone_deploy/projects/deploy_source_hasher.dart';
import 'package:phone_deploy/projects/deployable_project.dart';

void main() {
  test('viant_macos macOS hash reports unchanged after clean rewrite', () async {
    final projectPath =
        '/Users/Ethan/code/my-code/Active/Flutter/viant/apps/viant_macos';
    if (!Directory(projectPath).existsSync()) {
      return;
    }
    final status = await DeploySourceHasher.statusFor(
      projectPath: projectPath,
      platform: DeployPlatform.macos,
    );
    expect(status, DeploySourceStatus.unchanged);
  });
}
