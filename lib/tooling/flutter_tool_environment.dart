import 'dart:io';

import 'homebrew_ruby.dart';

/// Environment for spawning Flutter / xcodebuild / Ruby child processes.
///
/// Strips `GIT_CONFIG_*` that Copilot/Cursor inject into the host process
/// (`safe.bareRepository=explicit`). Those settings make SwiftPM reject its
/// bare-repo caches and surface as opaque `xcodebuild encountered an error (74)`.
///
/// Prepends Homebrew Ruby 3, Flutter, and Homebrew so LaunchAgent jobs do not
/// pick macOS `/usr/bin/ruby` 2.6.
Map<String, String> flutterToolEnvironment([Map<String, String>? base]) {
  final environment = Map<String, String>.from(base ?? Platform.environment);
  environment.removeWhere(
    (key, _) =>
        key == 'GIT_CONFIG_COUNT' ||
        key.startsWith('GIT_CONFIG_KEY_') ||
        key.startsWith('GIT_CONFIG_VALUE_'),
  );
  const toolchainBins = [
    HomebrewRuby.binDirectory,
    '/opt/homebrew/share/flutter/bin',
    '/opt/homebrew/bin',
  ];
  final path = environment['PATH'] ?? '';
  final missingBins = [
    for (final bin in toolchainBins)
      if (!path.split(':').contains(bin)) bin,
  ];
  if (missingBins.isNotEmpty) {
    environment['PATH'] = '${missingBins.join(':')}:$path';
  }
  environment['LANG'] = 'en_US.UTF-8';
  environment['LC_ALL'] = 'en_US.UTF-8';
  return environment;
}
