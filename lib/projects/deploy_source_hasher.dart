import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../deploy/deploy_platform.dart';
import 'workbench_project.dart';
import 'local_path_dependency_closure.dart';

/// Mirrors `deploy.rb` source hashing so change detection matches deploy skips.
abstract final class DeploySourceHasher() {
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
    DeploySourceHashMemo? memo,
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
      memo: memo,
    );
    if (currentHash == lastDeployedHash) {
      return DeploySourceStatus.unchanged;
    }
    return DeploySourceStatus.changed;
  }

  static Future<Map<DeployPlatform, DeploySourceStatus>> statusesFor({
    required String projectPath,
    required Iterable<DeployPlatform> platforms,
    DeploySourceHashMemo? memo,
  }) async {
    final statuses = <DeployPlatform, DeploySourceStatus>{};
    for (final platform in platforms) {
      statuses[platform] = await statusFor(
        projectPath: projectPath,
        platform: platform,
        memo: memo,
      );
    }
    return statuses;
  }

  /// Same inputs and ordering as `Deployer#source_hash` in deploy.rb.
  static Future<String> sourceHash({
    required String projectPath,
    required DeployPlatform platform,
    DeploySourceHashMemo? memo,
  }) async {
    final sourceFilePaths = await _sourceFiles(
      projectPath: projectPath,
      platform: platform,
      memo: memo,
    );
    final hashMemo = memo ?? DeploySourceHashMemo();
    final bytes = BytesBuilder(copy: false);
    for (final filePath in sourceFilePaths) {
      try {
        bytes.add(await hashMemo.bytesFor(filePath));
      } catch (_) {}
    }
    return md5.convert(bytes.toBytes()).toString();
  }

  static Future<List<String>> _sourceFiles({
    required String projectPath,
    required DeployPlatform platform,
    DeploySourceHashMemo? memo,
  }) async {
    final normalizedProjectPath = path.normalize(path.absolute(projectPath));
    final appSearchRoots = <String>[
      'lib',
      _platformDirectory(platform),
      'pubspec.yaml',
      'pubspec.lock',
    ];

    final hashMemo = memo ?? DeploySourceHashMemo();
    final sourceFilePaths = <String>{};
    for (final searchRoot in appSearchRoots) {
      sourceFilePaths.addAll(
        await hashMemo.filesUnder(
          packageRoot: normalizedProjectPath,
          relativeRoot: searchRoot,
        ),
      );
    }

    final localDependencyRoots = await LocalPathDependencyClosure(
      normalizedProjectPath,
    ).resolve();
    for (final localDependencyRoot in localDependencyRoots) {
      sourceFilePaths.addAll(
        await hashMemo.filesUnder(
          packageRoot: localDependencyRoot,
          relativeRoot: '.',
        ),
      );
    }
    return sourceFilePaths.toList()..sort();
  }

  static String _platformDirectory(DeployPlatform platform) =>
      switch (platform) {
        DeployPlatform.ios => path.join('ios', 'Runner'),
        DeployPlatform.macos => 'macos',
      };

  static bool isVolatileRelativePath(String relativePath) {
    final segments = path.split(relativePath);
    if (segments.contains('.DS_Store') ||
        path.basename(relativePath) == '.DS_Store') {
      return true;
    }
    return segments.any(_volatilePathSegments.contains);
  }
}

/// Reuses file lists and bytes across one evaluate-changes pass.
class DeploySourceHashMemo() {
  final Map<String, List<String>> _filesByRoot = {};
  final Map<String, Uint8List> _bytesByFile = {};

  Future<Uint8List> bytesFor(String filePath) async {
    final cachedBytes = _bytesByFile[filePath];
    if (cachedBytes != null) return cachedBytes;
    final fileBytes = await File(filePath).readAsBytes();
    _bytesByFile[filePath] = fileBytes;
    return fileBytes;
  }

  Future<List<String>> filesUnder({
    required String packageRoot,
    required String relativeRoot,
  }) async {
    final cacheKey = '$packageRoot::$relativeRoot';
    final cachedPaths = _filesByRoot[cacheKey];
    if (cachedPaths != null) return cachedPaths;
    final listedPaths = await _listFilesUnder(
      packageRoot: packageRoot,
      relativeRoot: relativeRoot,
    );
    _filesByRoot[cacheKey] = listedPaths;
    return listedPaths;
  }

  static Future<List<String>> _listFilesUnder({
    required String packageRoot,
    required String relativeRoot,
  }) async {
    final absoluteRoot = path.normalize(path.join(packageRoot, relativeRoot));
    final entityType = await FileSystemEntity.type(absoluteRoot);
    if (entityType == FileSystemEntityType.notFound) return const [];
    if (entityType == FileSystemEntityType.file) {
      return DeploySourceHasher.isVolatileRelativePath(relativeRoot)
          ? const []
          : [absoluteRoot];
    }

    final sourceFilePaths = <String>[];
    await for (final entity in Directory(
      absoluteRoot,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relativePath = path.relative(entity.path, from: packageRoot);
      if (DeploySourceHasher.isVolatileRelativePath(relativePath)) continue;
      sourceFilePaths.add(path.normalize(entity.path));
    }
    return sourceFilePaths;
  }
}
