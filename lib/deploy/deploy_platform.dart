enum DeployPlatform {
  ios,
  macos;

  static DeployPlatform fromName(String name) {
    return DeployPlatform.values.firstWhere(
      (platform) => platform.name == name,
      orElse: () => DeployPlatform.ios,
    );
  }

  String get label => switch (this) {
    DeployPlatform.ios => 'iOS',
    DeployPlatform.macos => 'macOS',
  };

  /// Argument passed to `deploy.rb`.
  String get scriptArgument => name;
}
