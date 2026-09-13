import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/projects/deploy_source_hasher.dart';
import 'package:ethan_workbench/projects/local_path_dependency_closure.dart';

void main() {
  late _DeployHashFixture fixture;

  setUp(() {
    fixture = _DeployHashFixture.create();
  });

  tearDown(() {
    fixture.delete();
  });

  test('direct local dependency source changes the hash', () async {
    final String originalHash = await fixture.dartHash();

    fixture.writeDirectSource('direct changed\n');

    expect(await fixture.dartHash(), isNot(originalHash));
  });

  test('transitive local dependency source changes the hash', () async {
    final String originalHash = await fixture.dartHash();

    fixture.writeTransitiveSource('transitive changed\n');

    expect(await fixture.dartHash(), isNot(originalHash));
  });

  test('unrelated sibling package does not change the hash', () async {
    final String originalHash = await fixture.dartHash();

    fixture.writeUnrelatedSource('unrelated changed\n');

    expect(await fixture.dartHash(), originalHash);
  });

  test('local dev dependency source does not change deploy hash', () async {
    final String originalHash = await fixture.dartHash();

    fixture.writeDevToolSource('dev tool changed\n');

    expect(await fixture.dartHash(), originalHash);
  });

  test('dependency cycles terminate with each package included once', () async {
    final localPackageRoots = await LocalPathDependencyClosure(
      fixture.appDirectory.path,
    ).resolve();

    expect(
      localPackageRoots,
      [
        fixture.directPackageDirectory.path,
        fixture.transitivePackageDirectory.path,
      ]..sort(),
    );
    expect(await fixture.dartHash(), isNotEmpty);
  });

  test('Dart source hash matches deploy.rb source hash mode', () async {
    expect(await fixture.dartHash(), await fixture.rubyHash());
  });
}

class _DeployHashFixture(final Directory fixtureDirectory) {
  static _DeployHashFixture create() {
    final fixtureDirectory = Directory.systemTemp.createTempSync(
      'ethan_workbench_hash_',
    );
    final fixture = _DeployHashFixture(fixtureDirectory);
    fixture._writeInitialTree();
    return fixture;
  }

  Directory get appDirectory =>
      Directory(path.join(fixtureDirectory.path, 'app'));

  Directory get directPackageDirectory =>
      Directory(path.join(fixtureDirectory.path, 'packages', 'direct'));

  Directory get transitivePackageDirectory =>
      Directory(path.join(fixtureDirectory.path, 'packages', 'transitive'));

  Directory get _unrelatedPackageDirectory =>
      Directory(path.join(fixtureDirectory.path, 'packages', 'unrelated'));

  Directory get _devToolPackageDirectory =>
      Directory(path.join(fixtureDirectory.path, 'packages', 'dev_tool'));

  Future<String> dartHash() => DeploySourceHasher.sourceHash(
    projectPath: appDirectory.path,
    platform: DeployPlatform.macos,
  );

  Future<String> rubyHash() async {
    final deployRubyFile = File(path.join(Directory.current.path, 'deploy.rb'));
    expect(deployRubyFile.existsSync(), isTrue);
    final rubyProcess = await Process.run('ruby', [
      deployRubyFile.path,
      'macos',
      '--print-source-hash',
    ], workingDirectory: appDirectory.path);
    expect(rubyProcess.exitCode, 0, reason: rubyProcess.stderr);
    return (rubyProcess.stdout as String).trim();
  }

  void writeDirectSource(String contents) {
    _writeFile(directPackageDirectory, 'lib/direct.dart', contents);
  }

  void writeTransitiveSource(String contents) {
    _writeFile(transitivePackageDirectory, 'lib/transitive.dart', contents);
  }

  void writeUnrelatedSource(String contents) {
    _writeFile(_unrelatedPackageDirectory, 'lib/unrelated.dart', contents);
  }

  void writeDevToolSource(String contents) {
    _writeFile(_devToolPackageDirectory, 'lib/dev_tool.dart', contents);
  }

  void delete() => fixtureDirectory.deleteSync(recursive: true);

  void _writeInitialTree() {
    _writeFile(appDirectory, 'pubspec.yaml', '''
name: sample
dependencies:
  direct:
    path: ../packages/direct
dev_dependencies:
  dev_tool:
    path: ../packages/dev_tool
''');
    _writeFile(appDirectory, 'pubspec.lock', 'lock\n');
    _writeFile(appDirectory, 'lib/main.dart', 'void main() {}\n');
    _writeFile(appDirectory, 'macos/Runner/App.swift', 'struct App {}\n');
    _writeFile(
      appDirectory,
      'lib/.dart_tool/noise.txt',
      'volatile app noise\n',
    );
    _writeFile(directPackageDirectory, 'pubspec.yaml', '''
name: direct
dependencies:
  transitive:
    path: ../transitive
''');
    writeDirectSource('direct\n');
    _writeFile(
      directPackageDirectory,
      '.dart_tool/noise.txt',
      'volatile dependency noise\n',
    );
    _writeFile(transitivePackageDirectory, 'pubspec.yaml', '''
name: transitive
dependencies:
  direct:
    path: ../direct
''');
    writeTransitiveSource('transitive\n');
    _writeFile(_unrelatedPackageDirectory, 'pubspec.yaml', 'name: unrelated\n');
    writeUnrelatedSource('unrelated\n');
    _writeFile(_devToolPackageDirectory, 'pubspec.yaml', 'name: dev_tool\n');
    writeDevToolSource('dev tool\n');
  }

  void _writeFile(
    Directory packageDirectory,
    String relativePath,
    String contents,
  ) {
    final file = File(path.join(packageDirectory.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }
}
