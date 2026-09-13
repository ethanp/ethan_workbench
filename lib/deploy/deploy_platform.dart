enum DeployPlatform({required final String label}) {
  ios(label: 'iOS'),
  macos(label: 'macOS');

  static DeployPlatform fromName(String name) {
    return DeployPlatform.values.firstWhere(
      (platform) => platform.name == name,
      orElse: () => DeployPlatform.ios,
    );
  }

  /// Argument passed to `deploy.rb`.
  String get scriptArgument => name;
}
