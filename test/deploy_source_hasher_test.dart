import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:phone_deploy/deploy/deploy_platform.dart';
import 'package:phone_deploy/projects/deploy_source_hasher.dart';

void main() {
  test('Dart source hash matches deploy.rb for a filtered tree', () async {
    final fixtureRoot =
        Directory.systemTemp.createTempSync('phone_deploy_hash_');
    addTearDown(() => fixtureRoot.deleteSync(recursive: true));

    final appDirectory = Directory(path.join(fixtureRoot.path, 'app'))
      ..createSync();
    final packagesDirectory =
        Directory(path.join(fixtureRoot.path, 'packages', 'shared'))
          ..createSync(recursive: true);

    File(path.join(appDirectory.path, 'pubspec.yaml'))
        .writeAsStringSync('name: sample\n');
    File(path.join(appDirectory.path, 'pubspec.lock'))
        .writeAsStringSync('lock\n');
    Directory(path.join(appDirectory.path, 'lib')).createSync();
    File(path.join(appDirectory.path, 'lib', 'main.dart'))
        .writeAsStringSync('void main() {}\n');
    Directory(path.join(appDirectory.path, 'macos', 'Runner'))
        .createSync(recursive: true);
    File(path.join(appDirectory.path, 'macos', 'Runner', 'App.swift'))
        .writeAsStringSync('struct App {}\n');

    // Volatile noise that must be ignored by both hashers.
    Directory(path.join(appDirectory.path, 'lib', '.dart_tool'))
        .createSync(recursive: true);
    File(path.join(appDirectory.path, 'lib', '.dart_tool', 'noise.txt'))
        .writeAsStringSync('noise\n');
    File(path.join(appDirectory.path, '.DS_Store')).writeAsStringSync('mac\n');
    File(path.join(packagesDirectory.path, 'code.dart'))
        .writeAsStringSync('shared\n');
    Directory(path.join(packagesDirectory.path, '.dart_tool'))
        .createSync(recursive: true);
    File(path.join(packagesDirectory.path, '.dart_tool', 'x'))
        .writeAsStringSync('x\n');

    final deployRb = File(
      path.join(
        Directory.current.path,
        'deploy.rb',
      ),
    );
    expect(deployRb.existsSync(), isTrue);

    final ruby = await Process.run(
      'ruby',
      ['-e', _rubyHashScript],
      workingDirectory: appDirectory.path,
    );
    expect(ruby.exitCode, 0, reason: ruby.stderr);
    final rubyHash = (ruby.stdout as String).trim();

    final dartHash = await DeploySourceHasher.sourceHash(
      projectPath: appDirectory.path,
      platform: DeployPlatform.macos,
    );

    expect(dartHash, rubyHash);
    expect(dartHash, isNotEmpty);
  });
}

const _rubyHashScript = r'''
require "digest"
require "find"

VOLATILE = %w[.dart_tool .git .idea .vscode build Pods node_modules]

def files_under(path)
  return [] unless File.exist?(path)
  return [path] unless File.directory?(path)
  Find.find(path).select do |file_path|
    next false unless File.file?(file_path)
    next false if File.basename(file_path) == ".DS_Store"
    next false if VOLATILE.any? { |s| file_path.split(File::SEPARATOR).include?(s) }
    true
  end
end

paths = (["lib", "macos", "pubspec.yaml", "pubspec.lock", "../../packages"]).flat_map { |p| files_under(p) }.sort
print Digest::MD5.hexdigest(paths.filter_map { |f| File.read(f) rescue nil }.join)
''';
