import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  final captureRb = File(
    path.join(Directory.current.path, 'xcodebuild_error_capture.rb'),
  );

  test('keeps unique xcodebuild: error lines and drops the rest', () async {
    expect(captureRb.existsSync(), isTrue);
    final fixtureDirectory = Directory.systemTemp.createTempSync(
      'xcodebuild_err_',
    );
    addTearDown(() => fixtureDirectory.deleteSync(recursive: true));
    final fixture = File(path.join(fixtureDirectory.path, 'stderr.txt'))
      ..writeAsStringSync('''
Resolve Package Graph
xcodebuild: error: Failed to build workspace Runner with scheme Runner.: This scheme builds an embedded Apple Watch app. watchOS 26.5 must be installed in order to run the scheme
note: Building targets in dependency order
xcodebuild: error: Failed to build workspace Runner with scheme Runner.: This scheme builds an embedded Apple Watch app. watchOS 26.5 must be installed in order to run the scheme
xcodebuild: error: Unable to find a destination matching the provided destination specifier:
''');
    final ruby = await Process.run('ruby', [captureRb.path, fixture.path]);
    expect(ruby.exitCode, 0, reason: '${ruby.stderr}');
    expect(
      ruby.stdout,
      'xcodebuild: error: Failed to build workspace Runner with scheme '
      'Runner.: This scheme builds an embedded Apple Watch app. watchOS 26.5 '
      'must be installed in order to run the scheme\n'
      'xcodebuild: error: Unable to find a destination matching the provided '
      'destination specifier:\n',
    );
  });

  test(
    'xcrun wrapper records xcodebuild stderr from the same process',
    () async {
      expect(captureRb.existsSync(), isTrue);
      final ruby = await Process.run('ruby', [
        '-e',
        '''
require "${captureRb.path}"
require "tmpdir"
Dir.mktmpdir("xcode-err-int-") do |directory|
  stub = File.join(directory, "real-xcrun")
  File.write(stub, "#!/bin/bash\\n" + "echo 'xcodebuild: error: watchOS 26.5 must be installed' >&2\\n" + "exit 1\\n")
  File.chmod(0o755, stub)
  capture = XcodebuildErrorCapture.new(directory, real_xcrun: stub)
  capture.install_xcrun_wrapper
  child_env = ENV.to_h.merge("PATH" => "#{directory}:#{ENV.fetch("PATH")}")
  system(child_env, "xcrun xcodebuild -scheme Runner")
  capture.print_hidden_errors
end
''',
      ]);
      expect(ruby.exitCode, 0, reason: '${ruby.stderr}');
      expect(ruby.stdout, contains('Xcode reported:'));
      expect(
        ruby.stdout,
        contains('xcodebuild: error: watchOS 26.5 must be installed'),
      );
    },
  );
}
