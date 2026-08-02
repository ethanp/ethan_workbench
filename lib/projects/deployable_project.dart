import 'dart:convert';
import 'dart:typed_data';

import '../deploy/deploy_platform.dart';

/// Result of comparing current sources to `.deploy_*_hash`.
enum DeploySourceStatus {
  /// CTA has not been run for this platform yet.
  unevaluated,
  neverDeployed,
  unchanged,
  changed;

  static DeploySourceStatus fromName(String name) {
    return DeploySourceStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => DeploySourceStatus.unevaluated,
    );
  }

  bool get isEvaluated => this != DeploySourceStatus.unevaluated;
}

class DeployableProject {
  final String projectId;
  final String name;
  final String path;
  final Set<DeployPlatform> platforms;
  final Map<DeployPlatform, DateTime?> lastDeployedAt;
  final Map<DeployPlatform, DeploySourceStatus> sourceStatus;
  final Uint8List? iconPngBytes;

  const DeployableProject({
    required this.projectId,
    required this.name,
    required this.path,
    required this.platforms,
    this.lastDeployedAt = const {},
    this.sourceStatus = const {},
    this.iconPngBytes,
  });

  bool supports(DeployPlatform platform) => platforms.contains(platform);

  DateTime? lastDeployedAtFor(DeployPlatform platform) =>
      lastDeployedAt[platform];

  DeploySourceStatus sourceStatusFor(DeployPlatform platform) =>
      sourceStatus[platform] ?? DeploySourceStatus.unevaluated;

  bool get hasChangedSources => platforms.any(
    (platform) => sourceStatusFor(platform) == DeploySourceStatus.changed,
  );

  DeployableProject copyWith({
    Map<DeployPlatform, DateTime?>? lastDeployedAt,
    Map<DeployPlatform, DeploySourceStatus>? sourceStatus,
    Uint8List? iconPngBytes,
  }) {
    return DeployableProject(
      projectId: projectId,
      name: name,
      path: path,
      platforms: platforms,
      lastDeployedAt: lastDeployedAt ?? this.lastDeployedAt,
      sourceStatus: sourceStatus ?? this.sourceStatus,
      iconPngBytes: iconPngBytes ?? this.iconPngBytes,
    );
  }

  factory DeployableProject.fromJson(Map<String, dynamic> json) {
    final platformNames = json['platforms'] as List<dynamic>?;
    final platforms = platformNames == null || platformNames.isEmpty
        ? {DeployPlatform.ios}
        : platformNames
              .map((name) => DeployPlatform.fromName(name as String))
              .toSet();
    final lastDeployedJson =
        json['lastDeployedAt'] as Map<String, dynamic>? ?? const {};
    final lastDeployedAt = <DeployPlatform, DateTime?>{
      for (final platform in platforms)
        platform: _parseOptionalDateTime(lastDeployedJson[platform.name]),
    };
    final sourceStatusJson =
        json['sourceStatus'] as Map<String, dynamic>? ?? const {};
    final sourceStatus = <DeployPlatform, DeploySourceStatus>{
      for (final platform in platforms)
        if (sourceStatusJson[platform.name] is String)
          platform: DeploySourceStatus.fromName(
            sourceStatusJson[platform.name] as String,
          ),
    };
    final iconBase64 = json['iconPngBase64'] as String?;
    return DeployableProject(
      projectId: json['projectId'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      platforms: platforms,
      lastDeployedAt: lastDeployedAt,
      sourceStatus: sourceStatus,
      iconPngBytes: iconBase64 == null || iconBase64.isEmpty
          ? null
          : base64Decode(iconBase64),
    );
  }

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    'name': name,
    'path': path,
    'platforms': platforms.map((platform) => platform.name).toList(),
    'lastDeployedAt': {
      for (final entry in lastDeployedAt.entries)
        if (entry.value != null) entry.key.name: entry.value!.toIso8601String(),
    },
    'sourceStatus': {
      for (final entry in sourceStatus.entries)
        if (entry.value.isEvaluated) entry.key.name: entry.value.name,
    },
    if (iconPngBytes != null) 'iconPngBase64': base64Encode(iconPngBytes!),
  };

  static DateTime? _parseOptionalDateTime(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
