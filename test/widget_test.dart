import 'package:flutter_test/flutter_test.dart';

import 'package:ethan_workbench/deploy/deploy_job.dart';

void main() {
  test('DeployJobStatus terminal flags', () {
    expect(DeployJobStatus.succeeded.isTerminal, isTrue);
    expect(DeployJobStatus.failed.isTerminal, isTrue);
    expect(DeployJobStatus.running.isTerminal, isFalse);
  });
}
