import 'dart:io';

/// Environment for spawning Flutter / xcodebuild child processes.
///
/// Strips `GIT_CONFIG_*` that Copilot/Cursor inject into the host process
/// (`safe.bareRepository=explicit`). Those settings make SwiftPM reject its
/// bare-repo caches and surface as opaque `xcodebuild encountered an error (74)`.
Map<String, String> flutterToolEnvironment([Map<String, String>? base]) {
  final environment = Map<String, String>.from(base ?? Platform.environment);
  environment.removeWhere(
    (key, _) =>
        key == 'GIT_CONFIG_COUNT' ||
        key.startsWith('GIT_CONFIG_KEY_') ||
        key.startsWith('GIT_CONFIG_VALUE_'),
  );
  return environment;
}
