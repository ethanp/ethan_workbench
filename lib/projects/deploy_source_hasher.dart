import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../deploy/deploy_platform.dart';
import 'deployable_project.dart';

/// Mirrors `deploy.rb` source hashing so change detection matches deploy skips.
abstract final class DeploySourceHasher {
  static const _volatilePathSegments = {
    '.dart_tool',
    '.git',
    '.idea',
    '.vscode',
    'build',
    'Pods',
    'node_modules',
  };

  static Future<DeploySourceStatus> statusFor({
    required String projectPath,
    required DeployPlatform platform,
  }) async {
    final hashFile = File(
      path.join(projectPath, '.deploy_${platform.name}_hash'),
    );
    if (!await hashFile.exists()) {
      return DeploySourceStatus.neverDeployed;
    }
    final lastDeployedHash = (await hashFile.readAsString()).trim();
    final currentHash = await sourceHash(
      projectPath: projectPath,
      platform: platform,
    );
    if (currentHash == lastDeployedHash) {
      return DeploySourceStatus.unchanged;
    }
    return DeploySourceStatus.changed;
  }

  static Future<Map<DeployPlatform, DeploySourceStatus>> statusesFor({
    required String projectPath,
    required Iterable<DeployPlatform> platforms,
  }) async {
    final statuses = <DeployPlatform, DeploySourceStatus>{};
    for (final platform in platforms) {
      statuses[platform] = await statusFor(
        projectPath: projectPath,
        platform: platform,
      );
    }
    return statuses;
  }

  /// Same inputs and ordering as `Deployer#source_hash` in deploy.rb.
  static Future<String> sourceHash({
    required String projectPath,
    required DeployPlatform platform,
  }) async {
    final sourceFilePaths = await _sourceFiles(
      projectPath: projectPath,
      platform: platform,
    );
    final bytes = BytesBuilder(copy: false);
    for (final filePath in sourceFilePaths) {
      try {
        bytes.add(await File(filePath).readAsBytes());
      } catch (_) {}
    }
    return md5.convert(bytes.toBytes()).toString();
  }

  static Future<List<String>> _sourceFiles({
    required String projectPath,
    required DeployPlatform platform,
  }) async {
    final searchRoots = <String>[
      'lib',
      _platformDirectory(platform),
      'pubspec.yaml',
      'pubspec.lock',
    ];
    final packagesRelative = path.join('..', '..', 'packages');
    if (await Directory(path.join(projectPath, packagesRelative)).exists()) {
      searchRoots.add(packagesRelative);
    }

    final relativeFilePaths = <String>[];
    for (final searchRoot in searchRoots) {
      relativeFilePaths.addAll(
        await _relativeFilesUnder(
          projectPath: projectPath,
          relativeRoot: searchRoot,
        ),
      );
    }
    relativeFilePaths.sort();
    return [
      for (final relativePath in relativeFilePaths)
        path.normalize(path.join(projectPath, relativePath)),
    ];
  }

  static String _platformDirectory(DeployPlatform platform) =>
      switch (platform) {
        DeployPlatform.ios => path.join('ios', 'Runner'),
        DeployPlatform.macos => 'macos',
      };

  static Future<List<String>> _relativeFilesUnder({
    required String projectPath,
    required String relativeRoot,
  }) async {
    final absoluteRoot = path.normalize(path.join(projectPath, relativeRoot));
    final entityType = await FileSystemEntity.type(absoluteRoot);
    if (entityType == FileSystemEntityType.notFound) return const [];
    if (entityType == FileSystemEntityType.file) {
      return _isVolatileRelativePath(relativeRoot) ? const [] : [relativeRoot];
    }

    final relativeFilePaths = <String>[];
    await for (final entity in Directory(
      absoluteRoot,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relativePath = path.relative(entity.path, from: projectPath);
      if (_isVolatileRelativePath(relativePath)) continue;
      relativeFilePaths.add(relativePath);
    }
    return relativeFilePaths;
  }

  static bool _isVolatileRelativePath(String relativePath) {
    final segments = path.split(relativePath);
    if (segments.contains('.DS_Store') ||
        path.basename(relativePath) == '.DS_Store') {
      return true;
    }
    return segments.any(_volatilePathSegments.contains);
  }
}
