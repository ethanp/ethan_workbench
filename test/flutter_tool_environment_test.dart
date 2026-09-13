import 'package:ethan_workbench/tooling/flutter_tool_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strips Copilot/Cursor GIT_CONFIG_* that break SwiftPM', () {
    final environment = flutterToolEnvironment({
      'PATH': '/usr/bin',
      'GIT_CONFIG_COUNT': '1',
      'GIT_CONFIG_KEY_0': 'safe.bareRepository',
      'GIT_CONFIG_VALUE_0': 'explicit',
      'HOME': '/Users/test',
    });

    expect(
      environment['PATH'],
      '/opt/homebrew/opt/ruby/bin:/opt/homebrew/share/flutter/bin:'
      '/opt/homebrew/bin:/usr/bin',
    );
    expect(environment['LANG'], 'en_US.UTF-8');
    expect(environment['LC_ALL'], 'en_US.UTF-8');
    expect(environment['HOME'], '/Users/test');
    expect(environment.containsKey('GIT_CONFIG_COUNT'), isFalse);
    expect(environment.containsKey('GIT_CONFIG_KEY_0'), isFalse);
    expect(environment.containsKey('GIT_CONFIG_VALUE_0'), isFalse);
  });
}
