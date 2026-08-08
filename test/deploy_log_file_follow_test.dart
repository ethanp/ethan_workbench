import 'package:ethan_workbench/deploy/deploy_log_file_follow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mergeDeployLogWithFile appends only unseen suffix', () {
    expect(
      mergeDeployLogWithFile('header\nab', 'abc\ndef'),
      'header\nabc\ndef',
    );
    expect(mergeDeployLogWithFile('abc', 'abc'), 'abc');
    expect(mergeDeployLogWithFile('', 'xyz'), 'xyz');
    expect(mergeDeployLogWithFile('keep\n', ''), 'keep\n');
  });

  test('mergeDeployLogWithFile prefers file when it already contains existing', () {
    expect(mergeDeployLogWithFile('ab', 'abcdef'), 'abcdef');
  });
}
