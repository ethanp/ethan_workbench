import 'dart:async';

import 'local_run_cursor_mirror.dart';
import 'local_run_key.dart';
import 'local_run_state.dart';

/// Published session snapshot + log for the UI.
///
/// One job: hold [LocalRunState], append log lines, and broadcast changes.
class LocalRunProgress({required final LocalRunKey runKey}) {
  static const logSnapshotInterval = Duration(milliseconds: 200);

  LocalRunState _current = LocalRunState.idle;
  final _changes = StreamController<LocalRunState>.broadcast();
  final _log = StringBuffer();
  Timer? _logSnapshotTimer;
  var _logDirty = false;
  bool _closed = false;

  LocalRunState get current => _current;
  Stream<LocalRunState> get changes => _changes.stream;
  bool get isActive => _current.status.isActive;
  bool get isClosed => _closed;
  String get logText => _log.toString();
  int get logLength => _log.length;

  void clearLog() {
    _log.clear();
    _cancelLogSnapshot();
    unawaited(LocalRunCursorMirror.clearLog(runKey));
    _publish(_current.copyWith(log: ''));
  }

  void emit(LocalRunState state) {
    _cancelLogSnapshot();
    _publish(state.copyWith(log: _log.toString()));
  }

  void appendLog(String chunk) {
    _log.write(chunk);
    unawaited(LocalRunCursorMirror.appendLog(runKey, chunk));
    _scheduleLogSnapshot();
  }

  /// After [stop], wait until status leaves `stopping` (or force-exit on timeout).
  Future<void> waitUntilNotStopping({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (_current.status != LocalRunStatus.stopping) return;
    final settled = Completer<void>();
    late final StreamSubscription<LocalRunState> subscription;
    subscription = changes.listen((state) {
      if (state.status != LocalRunStatus.stopping && !settled.isCompleted) {
        settled.complete();
      }
    });
    if (_current.status != LocalRunStatus.stopping) {
      await subscription.cancel();
      return;
    }
    try {
      await settled.future.timeout(
        timeout,
        onTimeout: () {
          if (_current.status == LocalRunStatus.stopping) {
            emit(
              _current.copyWith(
                status: LocalRunStatus.exited,
                readyForKeyCommands: false,
                reattached: false,
              ),
            );
          }
        },
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> close() async {
    _flushLogSnapshot();
    _closed = true;
    await _changes.close();
  }

  void _scheduleLogSnapshot() {
    if (_closed) return;
    _logDirty = true;
    _logSnapshotTimer ??= Timer(logSnapshotInterval, _flushLogSnapshot);
  }

  void _flushLogSnapshot() {
    _logSnapshotTimer = null;
    if (!_logDirty || _closed) return;
    _logDirty = false;
    _publish(_current.copyWith(log: _log.toString()));
  }

  void _cancelLogSnapshot() {
    _logSnapshotTimer?.cancel();
    _logSnapshotTimer = null;
    _logDirty = false;
  }

  void _publish(LocalRunState state) {
    _current = state;
    LocalRunCursorMirror.scheduleStatus(runKey, state);
    if (!_closed) {
      _changes.add(state);
    }
  }
}
