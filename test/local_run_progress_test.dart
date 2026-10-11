import 'package:ethan_workbench/run/local_run_key.dart';
import 'package:ethan_workbench/run/local_run_progress.dart';
import 'package:ethan_workbench/run/local_run_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('appendLog coalesces snapshots until the interval elapses', (
    tester,
  ) async {
    final progress = LocalRunProgress(
      runKey: LocalRunKey(projectId: 'book_track', deviceKey: 'meSim'),
    );
    addTearDown(progress.close);
    final snapshots = <LocalRunState>[];
    progress.changes.listen(snapshots.add);

    progress.appendLog('a');
    progress.appendLog('b');
    expect(snapshots, isEmpty);

    await tester.pump(LocalRunProgress.logSnapshotInterval);
    expect(snapshots, hasLength(1));
    expect(snapshots.single.log, 'ab');
    await tester.pump(const Duration(milliseconds: 150));
  });

  testWidgets('emit publishes immediately with the latest log', (tester) async {
    final progress = LocalRunProgress(
      runKey: LocalRunKey(projectId: 'book_track', deviceKey: 'meSim'),
    );
    addTearDown(progress.close);
    final snapshots = <LocalRunState>[];
    progress.changes.listen(snapshots.add);
    await tester.pump();

    progress.appendLog('log line\n');
    progress.emit(
      progress.current.copyWith(
        status: LocalRunStatus.running,
        readyForKeyCommands: true,
      ),
    );
    await tester.pump();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.status, LocalRunStatus.running);
    expect(snapshots.single.log, 'log line\n');
    await tester.pump(const Duration(milliseconds: 150));
  });
}
