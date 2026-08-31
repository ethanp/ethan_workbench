import 'dart:io';

import 'package:ethan_workbench/line_age/line_age_analyzer.dart';
import 'package:ethan_workbench/line_age/project_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('generated Dart suffixes stay on project source', () {
    expect(
      ProjectSource.generatedDartSuffixes,
      containsAll([
        '.g.dart',
        '.freezed.dart',
        '.gr.dart',
        '.gen.dart',
        '.mocks.dart',
      ]),
    );
  });

  test('skipped directories include Pods and the former Dart-only skips', () {
    expect(
      ProjectSource.skipDirectoryNames,
      containsAll({'.dart_tool', 'build', '.symlinks', 'Pods'}),
    );
  });

  test('findGitRoot walks up from a nested app folder', () {
    final root = Directory.systemTemp.createTempSync('line_age_git_');
    addTearDown(() => root.deleteSync(recursive: true));

    Directory(path.join(root.path, '.git')).createSync();
    final app = Directory(path.join(root.path, 'apps', 'viant_macos'))
      ..createSync(recursive: true);

    expect(LineAgeAnalyzer.findGitRoot(app.path), root.path);
    expect(LineAgeAnalyzer.findGitRoot(root.path), root.path);

    final outside = Directory.systemTemp.createTempSync('line_age_nogit_');
    addTearDown(() => outside.deleteSync(recursive: true));
    expect(LineAgeAnalyzer.findGitRoot(outside.path), isNull);
  });
}
