import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Dart and Swift lines that count toward line age and project size.
class ProjectSource.at(final String gitRoot) {
  List<File>? _countedFiles;

  static const generatedDartSuffixes = [
    '.g.dart',
    '.freezed.dart',
    '.gr.dart',
    '.gen.dart',
    '.mocks.dart',
  ];

  static const skipDirectoryNames = {
    '.dart_tool',
    'build',
    '.symlinks',
    'Pods',
  };

  List<File> get countedFiles => _countedFiles ??= _collectCountedFiles();

  List<String> get countedRelativePaths => [
    for (final file in countedFiles) path.relative(file.path, from: gitRoot),
  ];

  List<File> _collectCountedFiles() {
    final counted = <File>[];
    final queue = Queue<Directory>()..add(Directory(gitRoot));
    while (queue.isNotEmpty) {
      _enqueueOrCollect(queue.removeFirst(), queue, counted);
    }
    counted.sort((left, right) => left.path.compareTo(right.path));
    return counted;
  }

  void _enqueueOrCollect(
    Directory directory,
    Queue<Directory> queue,
    List<File> counted,
  ) {
    late final List<FileSystemEntity> children;
    try {
      children = directory.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final entity in children) {
      final name = path.basename(entity.path);
      if (entity is Directory) {
        if (skipDirectoryNames.contains(name) || name == '.git') continue;
        queue.add(entity);
        continue;
      }
      if (entity is! File) continue;
      if (!includes(path.relative(entity.path, from: gitRoot))) continue;
      counted.add(entity);
    }
  }

  bool includes(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    final segments = normalized.split('/');
    if (segments.any(_isSkippedDirectory)) return false;
    final name = segments.last;
    if (name.endsWith('.swift')) return true;
    if (!name.endsWith('.dart')) return false;
    return !generatedDartSuffixes.any(name.endsWith);
  }

  bool _isSkippedDirectory(String segment) =>
      skipDirectoryNames.contains(segment) || segment == '.git';

  int get lineCountAsOfToday {
    var lineCount = 0;
    for (final file in countedFiles) {
      lineCount += _lineCount(file);
    }
    return lineCount;
  }

  int _lineCount(File file) {
    try {
      return file.readAsLinesSync().length;
    } on FileSystemException {
      return 0;
    }
  }
}
