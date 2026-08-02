import 'dart:async';

import '../projects/deployable_project.dart';
import 'flutter_run_device.dart';
import 'local_flutter_run.dart';
import 'local_flutter_run_binding.dart';
import 'local_run_controls.dart';
import 'local_run_persistence.dart';
import 'local_run_progress.dart';
import 'local_run_state.dart';
import 'os_process_tree.dart';

/// Session policy for one local `flutter run`: start/stop/reclaim and when to persist.
///
/// Published run state lives in [LocalRunProgress]; process binding in
/// [LocalFlutterRunBinding].
class LocalRunSession implements LocalRunControls {
  LocalRunSession({
    this._isDeployBlocking,
    this._deployBlockMessage,
    LocalRunPersistence? persistence,
    LocalRunProgress? runProgress,
  }) : _persistence = persistence ?? LocalRunPersistence(),
       _runProgress = runProgress ?? LocalRunProgress();

  final bool Function()? _isDeployBlocking;
  final String? Function()? _deployBlockMessage;
  final LocalRunPersistence _persistence;
  final LocalRunProgress _runProgress;
  final LocalFlutterRunBinding _flutterRunBinding = LocalFlutterRunBinding();
  final PidLivenessWatch _liveness = PidLivenessWatch();
  bool _disposed = false;

  @override
  LocalRunState get state => _runProgress.current;
  @override
  Stream<LocalRunState> get updates => _runProgress.changes;
  @override
  bool get isActive => _runProgress.isActive;

  /// Restore a run orphaned by a workbench hot restart / relaunch.
  Future<void> restorePersisted() async {
    if (_disposed || _runProgress.isActive) return;
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
      if (_disposed) {
        await flutterRun.quit();
        return;
      }
      _liveness.cancel();
      _adoptFlutterRun(flutterRun);
      await _checkpoint(readyForKeyCommands: false);
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
        _watchOrphanPid(record.pid);
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

  @override
  Future<void> start(
    DeployableProject project, {
    required FlutterRunDevice device,
  }) async {
    if (_disposed) return;
    if (_runProgress.current.projectId == project.projectId &&
        _runProgress.current.deviceKey == device.key &&
        (_runProgress.current.status == LocalRunStatus.starting ||
            _runProgress.current.status == LocalRunStatus.running)) {
      return;
    }
    if (_runProgress.isActive) {
      throw LocalRunAlreadyActive(
        projectName: _runProgress.current.projectName ?? 'unknown',
        statusName: _runProgress.current.status.name,
      );
    }
    if (_isDeployBlocking?.call() ?? false) {
      throw DeployBlocksLocalRun(
        projectName: _deployBlockMessage?.call() ?? 'deploy',
        statusName: 'running',
      );
    }

    _liveness.cancel();
    _runProgress.clearLog();
    _flutterRunBinding.vmServiceUri = null;
    _runProgress.emit(
      LocalRunState(
        status: LocalRunStatus.starting,
        log: '',
        readyForKeyCommands: false,
        projectId: project.projectId,
        projectName: project.name,
        projectPath: project.path,
        deviceKey: device.key,
        deviceLabel: device.label,
        flutterDeviceId: device.flutterDeviceId,
        reattached: false,
      ),
    );

    try {
      if (device.prepareDeviceId != null) {
        _runProgress.appendLog('Preparing ${device.label}…\n');
      }
      final flutterDeviceId = await device.resolveFlutterDeviceId();
      if (_disposed) return;
      _runProgress.emit(
        _runProgress.current.copyWith(flutterDeviceId: flutterDeviceId),
      );
      if (device.prepareDeviceId != null) {
        _runProgress.appendLog('${device.label} ready ($flutterDeviceId).\n');
      }

      final flutterRun = await _flutterRunBinding.startNew(
        projectPath: project.path,
        deviceId: flutterDeviceId,
      );
      if (_disposed) {
        await flutterRun.quit();
        return;
      }
      _flutterRunBinding.trackedPid = flutterRun.pid;
      _adoptFlutterRun(flutterRun);
      await _checkpoint(readyForKeyCommands: false);
    } catch (error) {
      _flutterRunBinding.clearIdentity();
      await _persistence.clear();
      _runProgress.emit(
        _runProgress.current.copyWith(
          status: LocalRunStatus.failed,
          errorMessage: error.toString(),
          readyForKeyCommands: false,
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> hotReload() => _sendKeyCommand('r');

  @override
  Future<void> hotRestart() => _sendKeyCommand('R');

  @override
  Future<void> fullRestart() async {
    final projectId = _runProgress.current.projectId;
    final projectName = _runProgress.current.projectName;
    final projectPath = _runProgress.current.projectPath;
    final deviceKey = _runProgress.current.deviceKey;
    final deviceLabel = _runProgress.current.deviceLabel;
    final flutterDeviceId = _runProgress.current.flutterDeviceId;
    if (projectId == null ||
        projectName == null ||
        projectPath == null ||
        deviceKey == null ||
        deviceLabel == null ||
        flutterDeviceId == null) {
      return;
    }
    final device = deviceKey == FlutterRunDevice.meSim.key
        ? FlutterRunDevice.meSim
        : FlutterRunDevice.macos;
    try {
      await stop();
      if (_runProgress.isActive) {
        _runProgress.emit(
          _runProgress.current.copyWith(
            status: LocalRunStatus.exited,
            readyForKeyCommands: false,
            reattached: false,
          ),
        );
      }
      await start(
        DeployableProject(
          projectId: projectId,
          name: projectName,
          path: projectPath,
          platforms: const {},
        ),
        device: device,
      );
    } catch (error) {
      _runProgress.appendLog('Full restart failed: $error\n');
      if (!_runProgress.isActive) {
        _runProgress.emit(
          _runProgress.current.copyWith(
            status: LocalRunStatus.failed,
            errorMessage: error.toString(),
            readyForKeyCommands: false,
          ),
        );
      }
    }
  }

  @override
  Future<void> stop() async {
    if (!_flutterRunBinding.hasFlutterRun &&
        _flutterRunBinding.trackedPid == null) {
      if (_runProgress.isActive) {
        _runProgress.emit(
          _runProgress.current.copyWith(
            status: LocalRunStatus.exited,
            readyForKeyCommands: false,
            reattached: false,
          ),
        );
      }
      await _persistence.clear();
      return;
    }

    _runProgress.emit(
      _runProgress.current.copyWith(
        status: LocalRunStatus.stopping,
        readyForKeyCommands: false,
        clearError: true,
      ),
    );

    if (_flutterRunBinding.hasFlutterRun) {
      final flutterRun = _flutterRunBinding.flutterRun;
      final exitCode = await _flutterRunBinding.quit();
      if (flutterRun != null) {
        await _settleExit(flutterRun, exitCode, stoppedIntentionally: true);
      }
      await _runProgress.waitUntilNotStopping();
      return;
    }

    await _flutterRunBinding.quit();
    _liveness.cancel();
    await _persistence.clear();
    _runProgress.emit(
      _runProgress.current.copyWith(
        status: LocalRunStatus.exited,
        readyForKeyCommands: false,
        reattached: false,
        clearError: true,
      ),
    );
  }

  /// Detach without killing the app so a workbench hot restart can reclaim.
  Future<void> dispose() async {
    _disposed = true;
    _flutterRunBinding.invalidate();
    _liveness.cancel();
    await _flutterRunBinding.detachLeavingApp();
    await _runProgress.close();
  }

  void _adoptFlutterRun(LocalFlutterRun flutterRun) {
    _flutterRunBinding.adopt(
      flutterRun,
      onOutput: _onOutputChunk,
      onExit: (exitCode) {
        unawaited(
          _settleExit(flutterRun, exitCode, stoppedIntentionally: false),
        );
      },
    );
  }

  Future<void> _settleExit(
    LocalFlutterRun flutterRun,
    int exitCode, {
    required bool stoppedIntentionally,
  }) async {
    if (!_flutterRunBinding.owns(flutterRun)) return;
    _liveness.cancel();
    await _flutterRunBinding.releaseAfterExit(flutterRun);

    if (!_disposed) {
      final wasStopping =
          stoppedIntentionally ||
          _runProgress.current.status == LocalRunStatus.stopping;
      final failed = exitCode != 0 && !wasStopping;
      _runProgress.emit(
        _runProgress.current.copyWith(
          status: failed ? LocalRunStatus.failed : LocalRunStatus.exited,
          readyForKeyCommands: false,
          exitCode: exitCode,
          errorMessage: failed ? 'flutter run exited with $exitCode' : null,
          clearError: !failed,
          reattached: false,
        ),
      );
    }
    await _persistence.clear();
  }

  Future<void> _sendKeyCommand(String key) async {
    if (!_flutterRunBinding.hasFlutterRun ||
        !_runProgress.current.readyForKeyCommands) {
      return;
    }
    try {
      await _flutterRunBinding.sendKey(key);
      _runProgress.appendLog('→ sent $key\n');
    } catch (error) {
      _runProgress.appendLog('Failed to send $key: $error\n');
    }
  }

  void _onOutputChunk(String chunk) {
    _runProgress.appendLog(chunk);
    final parsedUri =
        FlutterRunOutput.vmServiceUriFrom(chunk) ??
        FlutterRunOutput.vmServiceUriFrom(_runProgress.logText);
    if (parsedUri != null && parsedUri != _flutterRunBinding.vmServiceUri) {
      _flutterRunBinding.vmServiceUri = parsedUri;
      unawaited(
        _checkpoint(
          readyForKeyCommands: _runProgress.current.readyForKeyCommands,
        ),
      );
    }
    if (_runProgress.current.readyForKeyCommands) return;
    final status = _runProgress.current.status;
    if (status == LocalRunStatus.stopping ||
        status == LocalRunStatus.exited ||
        status == LocalRunStatus.failed) {
      return;
    }
    if (FlutterRunOutput.looksReady(chunk) ||
        FlutterRunOutput.looksReady(_runProgress.logText)) {
      _runProgress.emit(
        _runProgress.current.copyWith(
          status: LocalRunStatus.running,
          readyForKeyCommands: true,
          clearError: true,
        ),
      );
      unawaited(_checkpoint(readyForKeyCommands: true));
    }
  }

  Future<void> _checkpoint({required bool readyForKeyCommands}) async {
    final pid = _flutterRunBinding.trackedPid;
    final projectId = _runProgress.current.projectId;
    final projectName = _runProgress.current.projectName;
    final projectPath = _runProgress.current.projectPath;
    final deviceKey = _runProgress.current.deviceKey;
    final deviceLabel = _runProgress.current.deviceLabel;
    final flutterDeviceId = _runProgress.current.flutterDeviceId;
    if (pid == null ||
        projectId == null ||
        projectName == null ||
        projectPath == null ||
        deviceKey == null ||
        deviceLabel == null ||
        flutterDeviceId == null) {
      return;
    }
    await _persistence.write(
      LocalRunRecord(
        pid: pid,
        projectId: projectId,
        projectName: projectName,
        projectPath: projectPath,
        readyForKeyCommands: readyForKeyCommands,
        deviceKey: deviceKey,
        deviceLabel: deviceLabel,
        flutterDeviceId: flutterDeviceId,
        vmServiceUri: _flutterRunBinding.vmServiceUri,
      ),
    );
  }

  void _watchOrphanPid(int pid) {
    _liveness.watch(
      pid,
      onDead: () async {
        if (_flutterRunBinding.hasFlutterRun || _disposed) return;
        if (_flutterRunBinding.trackedPid != pid) return;
        _flutterRunBinding.clearIdentity();
        await _persistence.clear();
        if (_runProgress.isActive) {
          _runProgress.appendLog('Reclaimed flutter run exited (pid $pid).\n');
          _runProgress.emit(
            _runProgress.current.copyWith(
              status: LocalRunStatus.exited,
              readyForKeyCommands: false,
              reattached: false,
            ),
          );
        }
      },
    );
  }
}
