import 'dart:io';

import 'package:path/path.dart' as path;

import '../deploy/deploy_platform.dart';
import 'project_app_icon.dart';
import 'workbench_project.dart';

/// Discovers pubspec projects under configured Flutter roots.
class const ProjectCatalog({required final List<String> flutterRoots}) {
  static const _skipDirectoryNames = {
    '.',
    '..',
    '.git',
    '.dart_tool',
    'build',
    'ios',
    'macos',
    'android',
    'linux',
    'windows',
    'web',
    'node_modules',
    'Pods',
    '.idea',
    '.vscode',
  };

  Future<List<WorkbenchProject>> listProjects() async {
    final discoveredProjects = <WorkbenchProject>[];
    final seenPaths = <String>{};

    for (final flutterRoot in flutterRoots) {
      final rootDirectory = Directory(flutterRoot);
      if (!await rootDirectory.exists()) continue;
      await _scanDirectory(
        directory: rootDirectory,
        flutterRoot: rootDirectory.absolute.path,
        depth: 0,
        discoveredProjects: discoveredProjects,
        seenPaths: seenPaths,
      );
    }

    discoveredProjects.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return discoveredProjects;
  }

  Future<void> _scanDirectory({
    required Directory directory,
    required String flutterRoot,
    required int depth,
    required List<WorkbenchProject> discoveredProjects,
    required Set<String> seenPaths,
  }) async {
    if (depth > 5) return;

    final directoryName = path.basename(directory.path);
    if (depth > 0 && _skipDirectoryNames.contains(directoryName)) return;

    final pubspecFile = File(path.join(directory.path, 'pubspec.yaml'));
    if (await pubspecFile.exists()) {
      final platforms = <DeployPlatform>{};
      if (await Directory(path.join(directory.path, 'ios')).exists()) {
        platforms.add(DeployPlatform.ios);
      }
      if (await Directory(path.join(directory.path, 'macos')).exists()) {
        platforms.add(DeployPlatform.macos);
      }
      final absolutePath = directory.absolute.path;
      if (seenPaths.add(absolutePath)) {
        final relativePath = path.relative(absolutePath, from: flutterRoot);
        discoveredProjects.add(
          WorkbenchProject(
            projectId: relativePath.split(path.separator).join('/'),
            name: directoryName,
            path: absolutePath,
            platforms: platforms,
            lastDeployedAt: await _lastDeployedAt(
              projectPath: absolutePath,
              platforms: platforms,
            ),
            iconPngBytes: await ProjectAppIcon.loadPngBytes(absolutePath),
          ),
        );
      }
      return;
    }

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! Directory) continue;
      await _scanDirectory(
        directory: entity,
        flutterRoot: flutterRoot,
        depth: depth + 1,
        discoveredProjects: discoveredProjects,
        seenPaths: seenPaths,
      );
    }
  }

  Future<Map<DeployPlatform, DateTime?>> _lastDeployedAt({
    required String projectPath,
    required Set<DeployPlatform> platforms,
  }) async {
    final lastDeployedAt = <DeployPlatform, DateTime?>{};
    for (final platform in platforms) {
      final hashFile = File(
        path.join(projectPath, '.deploy_${platform.name}_hash'),
      );
      if (!await hashFile.exists()) {
        lastDeployedAt[platform] = null;
        continue;
      }
      lastDeployedAt[platform] = await hashFile.lastModified();
    }
    return lastDeployedAt;
  }
}
