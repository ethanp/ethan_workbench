import 'dart:convert';
import 'dart:typed_data';

import 'package:ethan_ui/ethan_ui.dart';

import '../deploy/deploy_platform.dart';

enum DeploySourceStatus({
  required final String? chipLabel,
  required final EStatusTone? chipTone,
}) {
  unevaluated(chipLabel: null, chipTone: null),
  neverDeployed(chipLabel: null, chipTone: null),
  unchanged(chipLabel: 'current', chipTone: EStatusTone.success),
  changed(chipLabel: 'changed', chipTone: EStatusTone.warning);

  static DeploySourceStatus fromName(String name) {
    return DeploySourceStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => DeploySourceStatus.unevaluated,
    );
  }

  bool get isEvaluated => this != DeploySourceStatus.unevaluated;
}

class const WorkbenchProject({
  required final String projectId,
  required final String name,
  required final String path,
  required final Set<DeployPlatform> platforms,
  final Map<DeployPlatform, DateTime?> lastDeployedAt = const {},
  final Map<DeployPlatform, DeploySourceStatus> sourceStatus = const {},
  final Uint8List? iconPngBytes,
}) {
  bool get isDeployable => platforms.isNotEmpty;

  bool supports(DeployPlatform platform) => platforms.contains(platform);

  DateTime? lastDeployedAtFor(DeployPlatform platform) =>
      lastDeployedAt[platform];

  DeploySourceStatus sourceStatusFor(DeployPlatform platform) =>
      sourceStatus[platform] ?? DeploySourceStatus.unevaluated;

  bool get hasChangedSources => platforms.any(
    (platform) => sourceStatusFor(platform) == DeploySourceStatus.changed,
  );

  WorkbenchProject withSuccessfulDeploy({
    required DeployPlatform platform,
    required DateTime deployedAt,
  }) {
    return copyWith(
      lastDeployedAt: {...lastDeployedAt, platform: deployedAt},
      sourceStatus: {...sourceStatus, platform: DeploySourceStatus.unchanged},
    );
  }

  int compareByChangeThenName(WorkbenchProject other) {
    final changeOrder = (hasChangedSources ? 0 : 1).compareTo(
      other.hasChangedSources ? 0 : 1,
    );
    if (changeOrder != 0) return changeOrder;
    return name.toLowerCase().compareTo(other.name.toLowerCase());
  }

  WorkbenchProject copyWith({
    Map<DeployPlatform, DateTime?>? lastDeployedAt,
    Map<DeployPlatform, DeploySourceStatus>? sourceStatus,
    Uint8List? iconPngBytes,
  }) {
    return WorkbenchProject(
      projectId: projectId,
      name: name,
      path: path,
      platforms: platforms,
      lastDeployedAt: lastDeployedAt ?? this.lastDeployedAt,
      sourceStatus: sourceStatus ?? this.sourceStatus,
      iconPngBytes: iconPngBytes ?? this.iconPngBytes,
    );
  }

  factory fromJson(Map<String, dynamic> json) {
    final platformNames = json['platforms'] as List<dynamic>?;
    final platforms = platformNames == null
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
    return WorkbenchProject(
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
