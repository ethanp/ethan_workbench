import 'dart:convert';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

enum DiffLineKind({required final Color foreground}) {
  context(foreground: EColors.mono),
  insertion(foreground: EColors.success),
  deletion(foreground: EColors.danger),
  hunkHeader(foreground: EColors.textMuted);
}

class const UncommittedDiffLine({
  required final DiffLineKind kind,
  required final String text,
});

/// One file in the uncommitted patch (tracked edit or untracked add).
class const UncommittedFileDiff({
  required final String path,
  required final int added,
  required final int removed,
  required final List<UncommittedDiffLine> lines,
  final bool isBinary = false,
  final bool isUntracked = false,
}) {
  factory untracked({
    required String relativePath,
    required List<String> contentLines,
    required bool isBinary,
  }) {
    if (isBinary) {
      return UncommittedFileDiff(
        path: relativePath,
        added: 0,
        removed: 0,
        isBinary: true,
        isUntracked: true,
        lines: const [],
      );
    }
    return UncommittedFileDiff(
      path: relativePath,
      added: contentLines.length,
      removed: 0,
      isUntracked: true,
      lines: [
        UncommittedDiffLine(
          kind: DiffLineKind.hunkHeader,
          text: '@@ -0,0 +1,${contentLines.length} @@',
        ),
        for (final line in contentLines)
          UncommittedDiffLine(kind: DiffLineKind.insertion, text: line),
      ],
    );
  }

  bool get hasLineEdits => added > 0 || removed > 0;

  String get statCaption {
    if (isBinary) return isUntracked ? 'new binary' : 'binary';
    if (isUntracked && added == 0 && removed == 0) return 'new';
    return '+$added / -$removed';
  }
}

/// Unified diffs from `git diff HEAD`, split into files.
abstract final class UncommittedPatch() {
  static List<UncommittedFileDiff> fromGitDiff(String diff) {
    if (diff.trim().isEmpty) return const [];
    final files = <UncommittedFileDiff>[];
    _FileDiffBuilder? current;
    for (final line in const LineSplitter().convert(diff)) {
      if (line.startsWith('diff --git ')) {
        if (current != null) files.add(current.build());
        current = _FileDiffBuilder();
        continue;
      }
      current?.add(line);
    }
    if (current != null) files.add(current.build());
    return files;
  }
}

class _FileDiffBuilder() {
  String _path = '';
  String _deletedPath = '';
  var _added = 0;
  var _removed = 0;
  var _isBinary = false;
  final lines = <UncommittedDiffLine>[];

  void add(String line) {
    if (line.startsWith('Binary files ') || line.startsWith('GIT binary patch')) {
      _isBinary = true;
      return;
    }
    if (line.startsWith('+++ ')) {
      final parsed = _pathFromDiffMarker(line, '+++ ');
      if (parsed.isNotEmpty) _path = parsed;
      return;
    }
    if (line.startsWith('--- ')) {
      final parsed = _pathFromDiffMarker(line, '--- ');
      if (parsed.isNotEmpty) _deletedPath = parsed;
      return;
    }
    if (line.startsWith('@@')) {
      lines.add(UncommittedDiffLine(kind: DiffLineKind.hunkHeader, text: line));
      return;
    }
    if (line.startsWith('+')) {
      _added += 1;
      lines.add(
        UncommittedDiffLine(kind: DiffLineKind.insertion, text: line.substring(1)),
      );
      return;
    }
    if (line.startsWith('-')) {
      _removed += 1;
      lines.add(
        UncommittedDiffLine(kind: DiffLineKind.deletion, text: line.substring(1)),
      );
      return;
    }
    if (line.startsWith(' ') || line.isEmpty) {
      lines.add(
        UncommittedDiffLine(
          kind: DiffLineKind.context,
          text: line.isEmpty ? line : line.substring(1),
        ),
      );
    }
  }

  UncommittedFileDiff build() {
    return UncommittedFileDiff(
      path: _path.isNotEmpty ? _path : _deletedPath,
      added: _added,
      removed: _removed,
      isBinary: _isBinary,
      lines: lines,
    );
  }

  static String _pathFromDiffMarker(String line, String marker) {
    var rest = line.substring(marker.length);
    if (rest == '/dev/null') return '';
    if (rest.startsWith('"') && rest.endsWith('"')) {
      rest = rest.substring(1, rest.length - 1);
    }
    if (rest.startsWith('a/') || rest.startsWith('b/')) {
      return rest.substring(2);
    }
    return rest;
  }
}
