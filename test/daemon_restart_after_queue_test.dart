import 'package:ethan_workbench/server/daemon_restart_after_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restarts immediately when the queue is already idle', () {
    var restartCount = 0;
    final restartAfterQueue = DaemonRestartAfterQueue(
      isIdle: () => true,
      restartDaemon: () => restartCount++,
    );

    expect(restartAfterQueue.enqueue(), isTrue);
    expect(restartCount, 1);
    expect(restartAfterQueue.scheduled, isFalse);
  });

  test('waits for idle, then a later becameIdle restarts once', () {
    var idle = false;
    var restartCount = 0;
    final restartAfterQueue = DaemonRestartAfterQueue(
      isIdle: () => idle,
      restartDaemon: () => restartCount++,
    );

    expect(restartAfterQueue.enqueue(), isFalse);
    expect(restartAfterQueue.scheduled, isTrue);
    expect(restartCount, 0);

    restartAfterQueue.becameIdle();
    expect(restartCount, 0);

    idle = true;
    restartAfterQueue.becameIdle();
    expect(restartCount, 1);
    expect(restartAfterQueue.scheduled, isFalse);

    restartAfterQueue.becameIdle();
    expect(restartCount, 1);
  });
}
