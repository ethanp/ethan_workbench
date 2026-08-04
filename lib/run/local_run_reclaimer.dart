import 'local_flutter_run.dart';
import 'local_flutter_run_binding.dart';
import 'local_run_checkpoint.dart';
import 'local_run_console.dart';
import 'local_run_persistence.dart';
import 'local_run_progress.dart';
import 'local_run_state.dart';
import 'os_process_tree.dart';

/// Reclaims a `flutter run` left alive across workbench hot restart.
class LocalRunReclaimer {
  LocalRunReclaimer({
    required this._runProgress,
    required this._flutterRunBinding,
    required this._persistence,
    required this._checkpoint,
    required this._console,
    required this._adoptFlutterRun,
    required this._isDisposed,
  });

  final LocalRunProgress _runProgress;
  final LocalFlutterRunBinding _flutterRunBinding;
  final LocalRunPersistence _persistence;
  final LocalRunCheckpoint _checkpoint;
  final LocalRunConsole _console;
  final void Function(LocalFlutterRun flutterRun) _adoptFlutterRun;
  final bool Function() _isDisposed;
  final _liveness = PidLivenessWatch();

  void cancelLiveness() => _liveness.cancel();

  Future<void> restorePersisted() async {
    if (_isDisposed() || _runProgress.isActive) return;
    final record = await _persistence.read();
    if (record == null) return;

    final persistedRunStillAlive = await record.pid.asOsProcessTree.isAlive;
    final hasVmServiceUri =
        record.vmServiceUri != null && record.vmServiceUri!.isNotEmpty;
    if (!persistedRunStillAlive && !hasVmServiceUri) {
      await _persistence.clear();
      return;
    }

    _flutterRunBinding.trackedPid = persistedRunStillAlive ? record.pid : null;
    _flutterRunBinding.vmServiceUri = record.vmServiceUri;
    _runProgress.clearLog();
    _console.resetForNewRun();
    _runProgress.appendLog(
      'Reclaimed session after workbench restart'
      '${persistedRunStillAlive ? ' (pid ${record.pid})' : ''}.\n'
      'Attaching for hot reload…\n',
    );
    _runProgress.emit(
      LocalRunState(
        status: LocalRunStatus.starting,
        log: _runProgress.logText,
        readyForKeyCommands: false,
        projectId: record.projectId,
        projectName: record.projectName,
        projectPath: record.projectPath,
        deviceKey: record.deviceKey,
        deviceLabel: record.deviceLabel,
        flutterDeviceId: record.flutterDeviceId,
        reattached: true,
      ),
    );

    try {
      final flutterRun = await _flutterRunBinding.attachToRunning(
        projectPath: record.projectPath,
        deviceId: record.flutterDeviceId,
        vmServiceUri: record.vmServiceUri,
      );
      if (_isDisposed()) {
        await flutterRun.quit();
        return;
      }
      _liveness.cancel();
      _adoptFlutterRun(flutterRun);
      await _checkpoint.write(readyForKeyCommands: false);
      _runProgress.appendLog(
        'flutter attach started (pid ${flutterRun.pid}).\n',
      );
    } catch (error) {
      _runProgress.appendLog('flutter attach failed: $error\n');
      if (persistedRunStillAlive) {
        _runProgress.appendLog(
          'Hot reload unavailable until Full restart; Stop still works.\n',
        );
        _runProgress.emit(
          _runProgress.current.copyWith(
            status: LocalRunStatus.running,
            readyForKeyCommands: false,
            reattached: true,
          ),
        );
        watchOrphanPid(record.pid);
        return;
      }
      await _persistence.clear();
      _flutterRunBinding.clearIdentity();
      _runProgress.emit(
        _runProgress.current.copyWith(
          status: LocalRunStatus.exited,
          readyForKeyCommands: false,
          reattached: false,
          errorMessage: 'Could not reattach: $error',
        ),
      );
    }
  }

  void watchOrphanPid(int pid) {
    _liveness.watch(
      pid,
      onDead: () async {
        if (_flutterRunBinding.hasFlutterRun || _isDisposed()) return;
        if (_flutterRunBinding.trackedPid != pid) return;
        _flutterRunBinding.clearIdentity();
        await _persistence.clear();
        if (!_runProgress.isActive) return;
        _runProgress.appendLog('Reclaimed flutter run exited (pid $pid).\n');
        _runProgress.emit(
          _runProgress.current.copyWith(
            status: LocalRunStatus.exited,
            readyForKeyCommands: false,
            reattached: false,
          ),
        );
      },
    );
  }
}
