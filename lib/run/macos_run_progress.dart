import 'dart:async';

import 'macos_run_state.dart';

/// Published session snapshot + log for the UI.
///
/// One job: hold [MacosRunState], append log lines, and broadcast changes.
class MacosRunProgress {
  MacosRunState _current = MacosRunState.idle;
  final _changes = StreamController<MacosRunState>.broadcast();
  final _log = StringBuffer();
  bool _closed = false;

  MacosRunState get current => _current;
  Stream<MacosRunState> get changes => _changes.stream;
  bool get isActive => _current.status.isActive;
  bool get isClosed => _closed;
  String get logText => _log.toString();

  void clearLog() => _log.clear();

  void emit(MacosRunState state) {
    _current = state;
    if (!_closed) {
      _changes.add(state);
    }
  }

  void appendLog(String chunk) {
    _log.write(chunk);
    emit(_current.copyWith(log: _log.toString()));
  }

  /// After [stop], wait until status leaves `stopping` (or force-exit on timeout).
  Future<void> waitUntilNotStopping({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (_current.status != MacosRunStatus.stopping) return;
    final settled = Completer<void>();
    late final StreamSubscription<MacosRunState> subscription;
    subscription = changes.listen((state) {
      if (state.status != MacosRunStatus.stopping && !settled.isCompleted) {
        settled.complete();
      }
    });
    if (_current.status != MacosRunStatus.stopping) {
      await subscription.cancel();
      return;
    }
    try {
      await settled.future.timeout(
        timeout,
        onTimeout: () {
          if (_current.status == MacosRunStatus.stopping) {
            emit(
              _current.copyWith(
                status: MacosRunStatus.exited,
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
