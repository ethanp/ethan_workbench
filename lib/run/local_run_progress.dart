import 'dart:async';

import 'local_run_cursor_mirror.dart';
import 'local_run_state.dart';

/// Published session snapshot + log for the UI.
///
/// One job: hold [LocalRunState], append log lines, and broadcast changes.
class LocalRunProgress {
  LocalRunState _current = LocalRunState.idle;
  final _changes = StreamController<LocalRunState>.broadcast();
  final _log = StringBuffer();
  bool _closed = false;

  LocalRunState get current => _current;
  Stream<LocalRunState> get changes => _changes.stream;
  bool get isActive => _current.status.isActive;
  bool get isClosed => _closed;
  String get logText => _log.toString();

  void clearLog() {
    _log.clear();
    unawaited(LocalRunCursorMirror.clearLog());
  }

  void emit(LocalRunState state) {
    _current = state;
    LocalRunCursorMirror.scheduleStatus(state);
    if (!_closed) {
      _changes.add(state);
    }
  }

  void appendLog(String chunk) {
    _log.write(chunk);
    unawaited(LocalRunCursorMirror.appendLog(chunk));
    emit(_current.copyWith(log: _log.toString()));
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
    _closed = true;
    await _changes.close();
  }
}
