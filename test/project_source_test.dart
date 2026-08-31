import 'dart:io';

import 'package:ethan_workbench/line_age/project_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('project source includes Swift and excludes generated Dart and Pods', () {
    final root = Directory.systemTemp.createTempSync('project_source_');
    addTearDown(() => root.deleteSync(recursive: true));

    File(path.join(root.path, 'lib', 'a.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('class A {}\n');
    File(path.join(root.path, 'lib', 'a.g.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('// generated\n');
    File(path.join(root.path, 'macos', 'Runner', 'AppDelegate.swift'))
      ..createSync(recursive: true)
      ..writeAsStringSync('import Cocoa\n');
    File(path.join(root.path, 'ios', 'Pods', 'Foo', 'Foo.swift'))
      ..createSync(recursive: true)
      ..writeAsStringSync('enum Foo {}\n');

    final projectSource = ProjectSource.at(root.path);
    final relativePaths = [
      for (final file in projectSource.countedFiles)
        path.relative(file.path, from: root.path).replaceAll('\\', '/'),
    ]..sort();

    expect(relativePaths, [
      'lib/a.dart',
      'macos/Runner/AppDelegate.swift',
    ]);
    expect(projectSource.includes('lib/a.dart'), isTrue);
    expect(projectSource.includes('macos/Runner/AppDelegate.swift'), isTrue);
    expect(projectSource.includes('lib/a.g.dart'), isFalse);
    expect(projectSource.includes('ios/Pods/Foo/Foo.swift'), isFalse);
    expect(projectSource.lineCountAsOfToday, 2);
  });

  test('fingerprint changes when a Swift file is added', () {
    final root = Directory.systemTemp.createTempSync('project_source_fp_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(path.join(root.path, 'lib', 'a.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('class A {}\n');

    final before = ProjectSource.at(root.path).fingerprint;
    File(path.join(root.path, 'macos', 'Runner', 'AppDelegate.swift'))
      ..createSync(recursive: true)
      ..writeAsStringSync('import Cocoa\n');
    expect(ProjectSource.at(root.path).fingerprint, isNot(before));
  });
}
