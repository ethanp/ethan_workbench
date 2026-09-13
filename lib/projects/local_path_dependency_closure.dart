import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

class LocalPathDependencyClosure(String rootPackagePath) {
  final String _rootPackagePath = path.normalize(
    path.absolute(rootPackagePath),
  );

  Future<List<String>> resolve() async {
    final YamlMap? rootPubspec = await _readPubspec(_rootPackagePath);
    if (rootPubspec == null) return const [];
    final rootDependencyOverrides = _RootDependencyOverrides(
      rootPackagePath: _rootPackagePath,
      constraints: _dependencyConstraints(
        rootPubspec,
        sectionName: 'dependency_overrides',
      ),
    );
    final visitedPackageRoots = <String>{_rootPackagePath};
    final localPackageRoots = <String>[];
    await _visitDependenciesDeclaredBy(
      _rootPackagePath,
      rootDependencyOverrides: rootDependencyOverrides,
      visitedPackageRoots: visitedPackageRoots,
      localPackageRoots: localPackageRoots,
    );
    localPackageRoots.sort();
    return localPackageRoots;
  }

  Future<void> _visitDependenciesDeclaredBy(
    String declaringPackageRoot, {
    required _RootDependencyOverrides rootDependencyOverrides,
    required Set<String> visitedPackageRoots,
    required List<String> localPackageRoots,
  }) async {
    final YamlMap? pubspec = await _readPubspec(declaringPackageRoot);
    if (pubspec == null) return;

    final dependencies = _dependencyConstraints(
      pubspec,
      sectionName: 'dependencies',
    );
    for (final MapEntry<String, Object?> dependency in dependencies.entries) {
      final String? dependencyRoot = rootDependencyOverrides.localRootFor(
        dependencyName: dependency.key,
        declaredConstraint: dependency.value,
        declaringPackageRoot: declaringPackageRoot,
      );
      if (dependencyRoot == null) continue;
      if (!visitedPackageRoots.add(dependencyRoot)) continue;
      localPackageRoots.add(dependencyRoot);
      await _visitDependenciesDeclaredBy(
        dependencyRoot,
        rootDependencyOverrides: rootDependencyOverrides,
        visitedPackageRoots: visitedPackageRoots,
        localPackageRoots: localPackageRoots,
      );
    }
  }

  Future<YamlMap?> _readPubspec(String packageRoot) async {
    final pubspecFile = File(path.join(packageRoot, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) return null;
    final Object? pubspec = loadYaml(await pubspecFile.readAsString());
    return pubspec is YamlMap ? pubspec : null;
  }

  Map<String, Object?> _dependencyConstraints(
    YamlMap pubspec, {
    required String sectionName,
  }) {
    final Object? section = pubspec[sectionName];
    if (section is! YamlMap) return const {};
    return {
      for (final MapEntry<Object?, Object?> dependency in section.entries)
        if (dependency.key is String)
          dependency.key as String: dependency.value,
    };
  }
}

class _RootDependencyOverrides({
  required final String rootPackagePath,
  required final Map<String, Object?> constraints,
}) {
  String? localRootFor({
    required String dependencyName,
    required Object? declaredConstraint,
    required String declaringPackageRoot,
  }) {
    final bool isOverridden = constraints.containsKey(dependencyName);
    final Object? effectiveConstraint = isOverridden
        ? constraints[dependencyName]
        : declaredConstraint;
    if (effectiveConstraint is! YamlMap) return null;
    final Object? dependencyPath = effectiveConstraint['path'];
    if (dependencyPath is! String) return null;
    return path.normalize(
      path.absolute(
        path.join(
          isOverridden ? rootPackagePath : declaringPackageRoot,
          dependencyPath,
        ),
      ),
    );
  }
}
