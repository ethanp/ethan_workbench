/// Restarts the workbench daemon after the deploy queue is idle.
///
/// New deploys that land while this is scheduled just postpone the restart.
class DaemonRestartAfterQueue({
  required final bool Function() isIdle,
  required final void Function() restartDaemon,
}) {
  var scheduled = false;

  /// Arm the restart. Returns whether it began immediately because the queue
  /// was already idle.
  bool enqueue() {
    scheduled = true;
    return _restartIfIdle();
  }

  void becameIdle() {
    _restartIfIdle();
  }

  bool _restartIfIdle() {
    if (!scheduled) return false;
    if (!isIdle()) return false;
    scheduled = false;
    restartDaemon();
    return true;
  }
}
