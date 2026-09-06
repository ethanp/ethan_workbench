import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Dart and Swift lines that count toward line age and project size.
class ProjectSource.at(final String gitRoot) {
  List<File>? _countedFiles;
  String? _fingerprint;

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

  String get fingerprint => _fingerprint ??= _computeFingerprint();

  String _computeFingerprint() {
    final files = countedFiles;
    final parts = <String>[
      files.length.toString(),
      for (final file in files)
        '${path.relative(file.path, from: gitRoot)}:${_fileFingerprint(file)}',
    ];
    return Object.hashAll(parts).toString();
  }

  String _fileFingerprint(File file) {
    final stat = file.statSync();
    return '${stat.size}:'
        '${stat.modified.millisecondsSinceEpoch}:'
        '${stat.changed.millisecondsSinceEpoch}';
  }
}
