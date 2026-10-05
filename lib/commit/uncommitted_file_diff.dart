import 'dart:convert';
import 'dart:typed_data';

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

/// Working-tree and HEAD bytes for a raster image in the commit diff.
class const UncommittedImagePreview({
  final Uint8List? before,
  final Uint8List? after,
});

/// One file in the uncommitted patch (tracked edit or untracked add).
class const UncommittedFileDiff({
  required final String path,
  required final int added,
  required final int removed,
  required final List<UncommittedDiffLine> lines,
  final bool isBinary = false,
  final bool isUntracked = false,
  final String? pathAtHead,
  final UncommittedImagePreview? image,
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

  bool get isRasterImage {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
  }

  String get statCaption {
    final preview = image;
    if (preview != null) {
      if (preview.before == null) return 'new image';
      if (preview.after == null) return 'deleted image';
      return 'updated image';
    }
    if (isBinary) return isUntracked ? 'new binary' : 'binary';
    if (isUntracked && added == 0 && removed == 0) return 'new';
    return '+$added / -$removed';
  }

  UncommittedFileDiff showingImage(UncommittedImagePreview image) {
    return UncommittedFileDiff(
      path: path,
      added: added,
      removed: removed,
      lines: const [],
      isBinary: true,
      isUntracked: isUntracked,
      pathAtHead: pathAtHead,
      image: image,
    );
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
        current = _FileDiffBuilder(line);
        continue;
      }
      current?.add(line);
    }
    if (current != null) files.add(current.build());
    return files;
  }
}

class _FileDiffBuilder {
  _FileDiffBuilder(String diffGitLine) {
    final paths = _GitDiffPaths.parse(diffGitLine);
    _path = paths.after;
    _deletedPath = paths.before;
  }

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
    final path = _path.isNotEmpty ? _path : _deletedPath;
    final pathAtHead = _deletedPath.isNotEmpty && _deletedPath != path
        ? _deletedPath
        : null;
    return UncommittedFileDiff(
      path: path,
      added: _added,
      removed: _removed,
      isBinary: _isBinary,
      lines: lines,
      pathAtHead: pathAtHead,
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

class const _GitDiffPaths({
  required final String before,
  required final String after,
}) {
  static _GitDiffPaths parse(String diffGitLine) {
    final rest = diffGitLine.substring('diff --git '.length);
    if (rest.startsWith('"')) {
      final beforeToken = _QuotedGitPath.read(rest);
      var afterIndex = beforeToken.end;
      while (afterIndex < rest.length && rest[afterIndex] == ' ') {
        afterIndex += 1;
      }
      final afterToken = _QuotedGitPath.read(rest.substring(afterIndex));
      return _GitDiffPaths(
        before: _withoutAbPrefix(beforeToken.path),
        after: _withoutAbPrefix(afterToken.path),
      );
    }
    final splitAt = rest.lastIndexOf(' b/');
    if (splitAt < 0) return const _GitDiffPaths(before: '', after: '');
    return _GitDiffPaths(
      before: _withoutAbPrefix(rest.substring(0, splitAt)),
      after: _withoutAbPrefix(rest.substring(splitAt + 1)),
    );
  }

  static String _withoutAbPrefix(String path) {
    if (path.startsWith('a/') || path.startsWith('b/')) {
      return path.substring(2);
    }
    return path;
  }
}

class const _QuotedGitPath({
  required final String path,
  required final int end,
}) {
  static _QuotedGitPath read(String source) {
    if (!source.startsWith('"')) {
      return _QuotedGitPath(path: source, end: source.length);
    }
    final buffer = StringBuffer();
    var index = 1;
    while (index < source.length) {
      final char = source[index];
      if (char == '"') {
        return _QuotedGitPath(path: buffer.toString(), end: index + 1);
      }
      if (char != '\\' || index + 1 >= source.length) {
        buffer.write(char);
        index += 1;
        continue;
      }
      final escaped = source[index + 1];
      if (escaped == 'n') {
        buffer.write('\n');
        index += 2;
        continue;
      }
      if (escaped == 't') {
        buffer.write('\t');
        index += 2;
        continue;
      }
      if (escaped == '\\' || escaped == '"') {
        buffer.write(escaped);
        index += 2;
        continue;
      }
      if (escaped.compareTo('0') < 0 || escaped.compareTo('7') > 0) {
        buffer.write(escaped);
        index += 2;
        continue;
      }
      final octal = StringBuffer(escaped);
      var consumed = 2;
      while (consumed < 4 &&
          index + consumed < source.length &&
          source[index + consumed].compareTo('0') >= 0 &&
          source[index + consumed].compareTo('7') <= 0) {
        octal.write(source[index + consumed]);
        consumed += 1;
      }
      buffer.writeCharCode(int.parse(octal.toString(), radix: 8));
      index += consumed;
    }
    return _QuotedGitPath(path: buffer.toString(), end: source.length);
  }
}
