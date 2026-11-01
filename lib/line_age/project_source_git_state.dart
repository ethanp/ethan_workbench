import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'project_source.dart';

/// The git state line age was measured against: HEAD, plus a size/modified
/// stamp for every counted file whose content is not exactly HEAD's
/// (edited, staged, untracked, or ignored).
class const ProjectSourceGitState({
  required final String? headCommit,
  required final DateTime? headCommittedAt,
  required final Map<String, String> uncommittedFileStamps,
}) {
  static Future<ProjectSourceGitState> read(ProjectSource projectSource) async {
    final gitRoot = projectSource.gitRoot;
    final headLine = await _gitStdout(gitRoot, [
      'log',
      '-1',
      '--format=%H %ct',
      'HEAD',
    ]);
    final headParts = headLine?.trim().split(' ');
    final hasHead = headParts != null && headParts.length == 2;
    final committedAtSeconds = hasHead ? int.tryParse(headParts[1]) : null;
    final cleanPaths = hasHead
        ? await _pathsMatchingHead(gitRoot)
        : const <String>{};
    return ProjectSourceGitState(
      headCommit: hasHead ? headParts[0] : null,
      headCommittedAt: committedAtSeconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              committedAtSeconds * 1000,
              isUtc: true,
            ),
      uncommittedFileStamps: {
        for (final relativePath in projectSource.countedRelativePaths)
          if (!cleanPaths.contains(relativePath))
            relativePath: _fileStamp(path.join(gitRoot, relativePath)),
      },
    );
  }

  /// Counted paths whose blame may differ from when [analyzed] was read.
  /// Null when [analyzed] has no HEAD in this HEAD's history (rebase, amend,
  /// first commit), so every file must be reblamed.
  Future<Set<String>?> pathsToReblameSince(
    ProjectSourceGitState analyzed, {
    required String gitRoot,
  }) async {
    final analyzedHead = analyzed.headCommit;
    final currentHead = headCommit;
    if (analyzedHead == null || currentHead == null) return null;
    final reblamePaths = {
      ...analyzed.uncommittedFileStamps.keys,
      ...uncommittedFileStamps.keys,
    };
    if (analyzedHead == currentHead) return reblamePaths;

    final ancestorCheck = await Process.run('git', [
      'merge-base',
      '--is-ancestor',
      analyzedHead,
      currentHead,
    ], workingDirectory: gitRoot);
    if (ancestorCheck.exitCode != 0) return null;

    // -m lists files a merge commit itself changed (conflict resolutions).
    final touchedPaths = await _gitStdout(gitRoot, [
      'log',
      '-m',
      '--no-renames',
      '--name-only',
      '-z',
      '--format=',
      '$analyzedHead..$currentHead',
    ]);
    if (touchedPaths == null) return null;
    return reblamePaths..addAll(_nulSeparated(touchedPaths));
  }

  Map<String, Object?> toJson() => {
    'headCommit': headCommit,
    'headCommittedAt': headCommittedAt?.millisecondsSinceEpoch,
    'uncommittedFileStamps': uncommittedFileStamps,
  };

  /// Reports saved before git state was stored read as having no HEAD, which
  /// forces one full rerun.
  factory fromJson(Object? json) {
    if (json is! Map) {
      return const ProjectSourceGitState(
        headCommit: null,
        headCommittedAt: null,
        uncommittedFileStamps: {},
      );
    }
    final committedAtMillis = json['headCommittedAt'] as int?;
    return ProjectSourceGitState(
      headCommit: json['headCommit'] as String?,
      headCommittedAt: committedAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(committedAtMillis, isUtc: true),
      uncommittedFileStamps: {
        for (final entry
            in (json['uncommittedFileStamps'] as Map? ?? const {}).entries)
          entry.key as String: entry.value as String,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectSourceGitState &&
      other.headCommit == headCommit &&
      mapEquals(other.uncommittedFileStamps, uncommittedFileStamps);

  @override
  int get hashCode => Object.hash(
    headCommit,
    Object.hashAllUnordered(
      uncommittedFileStamps.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
  );

  /// Tracked paths whose working-tree content equals HEAD.
  static Future<Set<String>> _pathsMatchingHead(String gitRoot) async {
    final trackedPaths = await _gitStdout(gitRoot, ['ls-files', '-z']);
    final differingPaths = await _gitStdout(gitRoot, [
      'diff',
      '--name-only',
      '--no-renames',
      '-z',
      'HEAD',
    ]);
    if (trackedPaths == null || differingPaths == null) return const {};
    return _nulSeparated(trackedPaths).toSet()
      ..removeAll(_nulSeparated(differingPaths));
  }

  static String _fileStamp(String filePath) {
    final stat = FileStat.statSync(filePath);
    return '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
  }

  static Iterable<String> _nulSeparated(String output) => output
      .split('\u0000')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty);

  static Future<String?> _gitStdout(String gitRoot, List<String> args) async {
    final process = await Process.run(
      'git',
      args,
      workingDirectory: gitRoot,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (process.exitCode != 0) return null;
    return process.stdout as String;
  }
}
