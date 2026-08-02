import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/projects/deploy_source_hasher.dart';
import 'package:ethan_workbench/projects/deployable_project.dart';

void main() {
  test(
    'viant_macos macOS hash reports unchanged after clean rewrite',
    () async {
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
    },
  );
}
