import 'package:ethan_workbench/deploy/deploy_log_error_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('failureHint prefers the last error-looking line', () {
    const log = '''
Starting iOS deploy for workouts
Building…
** BUILD FAILED **
✗ Deploy failed (exit 1)
''';
    expect(
      DeployLogErrorSummary.failureHint(log),
      '✗ Deploy failed (exit 1)',
    );
  });

  test('errorTail keeps context around the first error in the window', () {
    final lines = [
      for (var index = 0; index < 10; index++) 'noise $index',
      'error: Signing for Runner requires a development team',
      'note: more detail',
      '✗ Deploy failed (exit 1)',
    ];
    final tail = DeployLogErrorSummary.errorTail(lines.join('\n'), maxLines: 40);
    expect(tail, contains('error: Signing'));
    expect(tail, contains('✗ Deploy failed'));
    expect(tail, isNot(contains('noise 0')));
  });
}
