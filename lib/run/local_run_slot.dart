import 'dart:async';

import '../projects/workbench_project.dart';
import 'flutter_run_device.dart';
import 'local_flutter_run.dart';
import 'local_flutter_run_binding.dart';
import 'local_run_checkpoint.dart';
import 'local_run_console.dart';
import 'local_run_controls.dart';
import 'local_run_key.dart';
import 'local_run_persistence.dart';
import 'local_run_progress.dart';
import 'local_run_reclaimer.dart';
import 'local_run_state.dart';
import 'running_app_vm.dart';

/// Session policy for one local `flutter run`: start/stop/reclaim.
///
/// Published run state lives in [LocalRunProgress]; process binding in
/// [LocalFlutterRunBinding]; console interpretation in [LocalRunConsole];
/// hot-restart reclaim in [LocalRunReclaimer].
class LocalRunSlot({
  required final LocalRunKey _runKey,
  LocalRunPersistence? persistence,
}) implements LocalRunControls {
  this {
    _flutterRunBinding = LocalFlutterRunBinding();
    _checkpoint = LocalRunCheckpoint(
      runKey: _runKey,
      runProgress: _runProgress,
      flutterRunBinding: _flutterRunBinding,
      persistence: _persistence,
    );
    _console = LocalRunConsole(
      runProgress: _runProgress,
      flutterRunBinding: _flutterRunBinding,
      checkpoint: _checkpoint,
      onAttachGaveUpOnVmService: () {
        unawaited(_stopAttachThatCannotReachVmService());
      },
      onVmServiceUriCaptured: () {
        if (!_runProgress.current.infoLogs) return;
        unawaited(_reconnectInfoLogs());
      },
    );
    _reclaimer = LocalRunReclaimer(
      runKey: _runKey,
      runProgress: _runProgress,
      flutterRunBinding: _flutterRunBinding,
      persistence: _persistence,
      checkpoint: _checkpoint,
      console: _console,
      adoptFlutterRun: _adoptFlutterRun,
      isDisposed: () => _disposed,
    );
  }

  final LocalRunPersistence _persistence = persistence ?? LocalRunPersistence();
  final LocalRunProgress _runProgress = LocalRunProgress(runKey: _runKey);
  late final LocalFlutterRunBinding _flutterRunBinding;
  late final LocalRunCheckpoint _checkpoint;
  late final LocalRunConsole _console;
  late final LocalRunReclaimer _reclaimer;
  bool _disposed = false;
  RunningAppVm? _infoLogsVm;
  StreamSubscription<String>? _infoLogsSubscription;

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
    WorkbenchProject project, {
    required FlutterRunDevice device,
  }) async {
    if (_disposed) return;
    if (_runProgress.current.status == LocalRunStatus.starting ||
        _runProgress.current.status == LocalRunStatus.running) {
      return;
    }
    if (_runProgress.current.status == LocalRunStatus.stopping) {
      return;
    }

    _reclaimer.cancelLiveness();
    _runProgress.clearLog();
    _console.resetForNewRun();
    _flutterRunBinding.vmServiceUri = null;
    _flutterRunBinding.deviceVmServiceUri = null;
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
    final int logLengthBeforeRestart = _runProgress.current.log.length;
    await _sendKeyCommand('R');
    unawaited(_killIsolatesLeftFromBeforeRestart(logLengthBeforeRestart));
  }

  /// Once the restart banner prints, kills isolates the old run left behind
  /// (PowerSync's sync isolate survives a hot restart and keeps working).
  Future<void> _killIsolatesLeftFromBeforeRestart(
    int logLengthBeforeRestart,
  ) async {
    final String? vmServiceUri = _flutterRunBinding.vmServiceUri;
    if (vmServiceUri == null) return;
    try {
      await _runProgress.changes
          .firstWhere(
            (runState) =>
                runState.log.indexOf(
                  'Restarted application in',
                  logLengthBeforeRestart,
                ) >=
                0,
          )
          .timeout(const Duration(minutes: 1));
      final runningAppVm = await RunningAppVm.connect(vmServiceUri);
      try {
        final List<String> killedNames = await runningAppVm
            .killIsolatesLeftFromBeforeRestart();
        if (killedNames.isEmpty) return;
        _runProgress.appendLog(
          'Killed isolates left from before the restart: '
          '${killedNames.join(', ')}\n',
        );
      } finally {
        await runningAppVm.dispose();
      }
    } catch (error) {
      _runProgress.appendLog(
        'Could not clean up isolates after restart: $error\n',
      );
    }
  }

  @override
  Future<String> evaluateInApp(
    String expression, {
    String? librarySuffix,
  }) async {
    final String? vmServiceUri = _flutterRunBinding.vmServiceUri;
    if (vmServiceUri == null) {
      throw StateError('This run has no VM service yet');
    }
    final runningAppVm = await RunningAppVm.connect(vmServiceUri);
    try {
      return await runningAppVm.evaluateInMainIsolate(
        expression,
        librarySuffix: librarySuffix ?? RunningAppVm.appLogBufferLibrarySuffix,
      );
    } finally {
      await runningAppVm.dispose();
    }
  }

  @override
  Future<void> setInfoLogs(bool enabled) async {
    if (_runProgress.current.infoLogs != enabled) {
      _runProgress.emit(_runProgress.current.copyWith(infoLogs: enabled));
    }
    if (!enabled) {
      await _stopInfoLogs();
      return;
    }
    await _streamInfoLogs();
  }

  /// Appends each app log line to the run log as the app writes it. Waits
  /// silently until `flutter run` has printed the VM service URI; the console
  /// calls back then.
  Future<void> _streamInfoLogs() async {
    final String? vmServiceUri = _flutterRunBinding.vmServiceUri;
    if (vmServiceUri == null || _infoLogsVm != null) return;
    try {
      final runningAppVm = await RunningAppVm.connect(vmServiceUri);
      if (!_runProgress.current.infoLogs || _infoLogsVm != null) {
        await runningAppVm.dispose();
        return;
      }
      _infoLogsVm = runningAppVm;
      _infoLogsSubscription = runningAppVm.appLogLines().listen(
        (line) => _runProgress.appendLog(line.endsWith('\n') ? line : '$line\n'),
        onError: (Object error) {
          _runProgress.appendLog('Info logs stopped: $error\n');
          unawaited(_stopInfoLogs());
        },
        onDone: () => unawaited(_stopInfoLogs()),
      );
      _runProgress.appendLog('Info logs on.\n');
    } catch (error) {
      _runProgress.appendLog('Could not stream info logs: $error\n');
    }
  }

  /// A full restart prints a new VM service URI; follow it.
  Future<void> _reconnectInfoLogs() async {
    await _stopInfoLogs();
    await _streamInfoLogs();
  }

  Future<void> _stopInfoLogs() async {
    final StreamSubscription<String>? subscription = _infoLogsSubscription;
    final RunningAppVm? runningAppVm = _infoLogsVm;
    _infoLogsSubscription = null;
    _infoLogsVm = null;
    await subscription?.cancel();
    await runningAppVm?.dispose();
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
        WorkbenchProject(
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

  Future<void> _stopAttachThatCannotReachVmService() async {
    if (!_runProgress.current.reattached) return;
    if (_runProgress.current.readyForKeyCommands) return;
    if (_runProgress.current.status != LocalRunStatus.starting) return;
    _runProgress.appendLog(
      'flutter attach kept retrying a VM service that refused the connection. '
      'Stopping it.\n',
    );
    await stop();
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
        await _recordExitAsFailedOrExited(
          flutterRun,
          exitCode,
          stoppedIntentionally: true,
        );
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
    await _stopInfoLogs();
    _flutterRunBinding.invalidate();
    _reclaimer.cancelLiveness();
    await _flutterRunBinding.detachLeavingApp();
    await _runProgress.close();
  }

  void _adoptFlutterRun(LocalFlutterRun flutterRun) {
    _console.bindFlutterRunOutput(
      _flutterRunBinding,
      flutterRun,
      onExit: (exitCode) {
        unawaited(
          _recordExitAsFailedOrExited(
            flutterRun,
            exitCode,
            stoppedIntentionally: false,
          ),
        );
      },
    );
  }

  Future<void> _recordExitAsFailedOrExited(
    LocalFlutterRun flutterRun,
    int exitCode, {
    required bool stoppedIntentionally,
  }) async {
    if (!_flutterRunBinding.owns(flutterRun)) return;
    _reclaimer.cancelLiveness();
    await _stopInfoLogs();
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
