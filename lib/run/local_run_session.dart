import 'dart:async';

import '../projects/deployable_project.dart';
import 'flutter_run_device.dart';
import 'local_flutter_run.dart';
import 'local_flutter_run_binding.dart';
import 'local_run_checkpoint.dart';
import 'local_run_console.dart';
import 'local_run_controls.dart';
import 'local_run_persistence.dart';
import 'local_run_progress.dart';
import 'local_run_reclaimer.dart';
import 'local_run_state.dart';

/// Session policy for one local `flutter run`: start/stop/reclaim.
///
/// Published run state lives in [LocalRunProgress]; process binding in
/// [LocalFlutterRunBinding]; console interpretation in [LocalRunConsole];
/// hot-restart reclaim in [LocalRunReclaimer].
class LocalRunSession implements LocalRunControls {
  LocalRunSession({
    this._isDeployBlocking,
    this._deployBlockMessage,
    LocalRunPersistence? persistence,
    LocalRunProgress? runProgress,
  }) : _persistence = persistence ?? LocalRunPersistence(),
       _runProgress = runProgress ?? LocalRunProgress() {
    _flutterRunBinding = LocalFlutterRunBinding();
    _checkpoint = LocalRunCheckpoint(
      runProgress: _runProgress,
      flutterRunBinding: _flutterRunBinding,
      persistence: _persistence,
    );
    _console = LocalRunConsole(
      runProgress: _runProgress,
      flutterRunBinding: _flutterRunBinding,
      checkpoint: _checkpoint,
    );
    _reclaimer = LocalRunReclaimer(
      runProgress: _runProgress,
      flutterRunBinding: _flutterRunBinding,
      persistence: _persistence,
      checkpoint: _checkpoint,
      console: _console,
      adoptFlutterRun: _adoptFlutterRun,
      isDisposed: () => _disposed,
    );
  }

  final bool Function()? _isDeployBlocking;
  final String? Function()? _deployBlockMessage;
  final LocalRunPersistence _persistence;
  final LocalRunProgress _runProgress;
  late final LocalFlutterRunBinding _flutterRunBinding;
  late final LocalRunCheckpoint _checkpoint;
  late final LocalRunConsole _console;
  late final LocalRunReclaimer _reclaimer;
  bool _disposed = false;

  @override
  LocalRunState get state => _runProgress.current;
  @override
  Stream<LocalRunState> get updates => _runProgress.changes;
  @override
  bool get isActive => _runProgress.isActive;

  /// Restore a run orphaned by a workbench hot restart / relaunch.
  Future<void> restorePersisted() => _reclaimer.restorePersisted();

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

    _reclaimer.cancelLiveness();
    _runProgress.clearLog();
    _console.resetForNewRun();
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
      await _checkpoint.write(readyForKeyCommands: false);
    } catch (error) {
      _flutterRunBinding.clearIdentity();
      await _checkpoint.clear();
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
  Future<void> hotReload() async {
    _console.clearFlutterException();
    await _sendKeyCommand('r');
  }

  @override
  Future<void> hotRestart() async {
    _console.clearFlutterException();
    await _sendKeyCommand('R');
  }

  @override
  Future<void> fullRestart() async {
    _console.clearFlutterException();
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
      await _checkpoint.clear();
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
    _reclaimer.cancelLiveness();
    await _checkpoint.clear();
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
    _reclaimer.cancelLiveness();
    await _flutterRunBinding.detachLeavingApp();
    await _runProgress.close();
  }

  void _adoptFlutterRun(LocalFlutterRun flutterRun) {
    _flutterRunBinding.adopt(
      flutterRun,
      onOutput: _console.onOutputChunk,
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
    _reclaimer.cancelLiveness();
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
    await _checkpoint.clear();
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
}
