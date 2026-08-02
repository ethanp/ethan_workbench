import 'dart:async';

import '../projects/deployable_project.dart';
import 'macos_flutter_run.dart';
import 'macos_run_handle.dart';
import 'macos_run_persistence.dart';
import 'macos_run_progress.dart';
import 'macos_run_state.dart';

/// Session policy for one macOS app run: start/stop/reclaim and when to persist.
///
/// Progress UI state lives in [MacosRunProgress]; OS tools binding in [MacosRunHandle].
class MacosRunSession {
  MacosRunSession({
    this._isDeployBlocking,
    this._deployBlockMessage,
    MacosRunPersistence? persistence,
    MacosRunProgress? progress,
  }) : _persistence = persistence ?? MacosRunPersistence(),
       _progress = progress ?? MacosRunProgress();

  final bool Function()? _isDeployBlocking;
  final String? Function()? _deployBlockMessage;
  final MacosRunPersistence _persistence;
  final MacosRunProgress _progress;
  final MacosRunHandle _handle = MacosRunHandle();
  final PidLivenessWatch _liveness = PidLivenessWatch();
  bool _disposed = false;

  MacosRunState get state => _progress.current;
  Stream<MacosRunState> get updates => _progress.changes;
  bool get isActive => _progress.isActive;

  /// Restore a run orphaned by a workbench hot restart / relaunch.
  Future<void> restorePersisted() async {
    if (_disposed || _progress.isActive) return;
    final record = await _persistence.read();
    if (record == null) return;

    final toolsAlive = await MacosFlutterRun.isPidAlive(record.pid);
    final hasVmServiceUri =
        record.vmServiceUri != null && record.vmServiceUri!.isNotEmpty;
    if (!toolsAlive && !hasVmServiceUri) {
      await _persistence.clear();
      return;
    }

    _handle.trackedPid = toolsAlive ? record.pid : null;
    _handle.vmServiceUri = record.vmServiceUri;
    _progress.clearLog();
    _progress.appendLog(
      'Reclaimed session after workbench restart'
      '${toolsAlive ? ' (pid ${record.pid})' : ''}.\n'
      'Attaching for hot reload…\n',
    );
    _progress.emit(
      MacosRunState(
        status: MacosRunStatus.starting,
        log: _progress.logText,
        readyForKeyCommands: false,
        projectId: record.projectId,
        projectName: record.projectName,
        projectPath: record.projectPath,
        reattached: true,
      ),
    );

    try {
      final tools = await _handle.attachToRunning(
        projectPath: record.projectPath,
        vmServiceUri: record.vmServiceUri,
      );
      if (_disposed) {
        await tools.quit();
        return;
      }
      _liveness.cancel();
      _adoptTools(tools);
      await _checkpoint(readyForKeyCommands: false);
      _progress.appendLog('flutter attach started (pid ${tools.pid}).\n');
    } catch (error) {
      _progress.appendLog('flutter attach failed: $error\n');
      if (toolsAlive) {
        _progress.appendLog(
          'Hot reload unavailable until Full restart; Stop still works.\n',
        );
        _progress.emit(
          _progress.current.copyWith(
            status: MacosRunStatus.running,
            readyForKeyCommands: false,
            reattached: true,
          ),
        );
        _watchOrphanPid(record.pid);
        return;
      }
      await _persistence.clear();
      _handle.clearIdentity();
      _progress.emit(
        _progress.current.copyWith(
          status: MacosRunStatus.exited,
          readyForKeyCommands: false,
          reattached: false,
          errorMessage: 'Could not reattach: $error',
        ),
      );
    }
  }

  Future<void> start(DeployableProject project) async {
    if (_disposed) return;
    if (_progress.current.projectId == project.projectId &&
        (_progress.current.status == MacosRunStatus.starting ||
            _progress.current.status == MacosRunStatus.running)) {
      return;
    }
    if (_progress.isActive) {
      throw MacosRunAlreadyActive(
        projectName: _progress.current.projectName ?? 'unknown',
        statusName: _progress.current.status.name,
      );
    }
    if (_isDeployBlocking?.call() ?? false) {
      throw DeployBlocksMacosRun(
        projectName: _deployBlockMessage?.call() ?? 'deploy',
        statusName: 'running',
      );
    }

    _liveness.cancel();
    _progress.clearLog();
    _handle.vmServiceUri = null;
    _progress.emit(
      MacosRunState(
        status: MacosRunStatus.starting,
        log: '',
        readyForKeyCommands: false,
        projectId: project.projectId,
        projectName: project.name,
        projectPath: project.path,
        reattached: false,
      ),
    );

    try {
      final tools = await _handle.startNew(project.path);
      if (_disposed) {
        await tools.quit();
        return;
      }
      _handle.trackedPid = tools.pid;
      _adoptTools(tools);
      await _checkpoint(readyForKeyCommands: false);
    } catch (error) {
      _handle.clearIdentity();
      await _persistence.clear();
      _progress.emit(
        _progress.current.copyWith(
          status: MacosRunStatus.failed,
          errorMessage: error.toString(),
          readyForKeyCommands: false,
        ),
      );
      rethrow;
    }
  }

  Future<void> hotReload() => _sendKeyCommand('r');

  Future<void> hotRestart() => _sendKeyCommand('R');

  Future<void> fullRestart() async {
    final projectId = _progress.current.projectId;
    final projectName = _progress.current.projectName;
    final projectPath = _progress.current.projectPath;
    if (projectId == null || projectName == null || projectPath == null) {
      return;
    }
    try {
      await stop();
      if (_progress.isActive) {
        _progress.emit(
          _progress.current.copyWith(
            status: MacosRunStatus.exited,
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
      );
    } catch (error) {
      _progress.appendLog('Full restart failed: $error\n');
      if (!_progress.isActive) {
        _progress.emit(
          _progress.current.copyWith(
            status: MacosRunStatus.failed,
            errorMessage: error.toString(),
            readyForKeyCommands: false,
          ),
        );
      }
    }
  }

  Future<void> stop() async {
    if (!_handle.hasLiveTools && _handle.trackedPid == null) {
      if (_progress.isActive) {
        _progress.emit(
          _progress.current.copyWith(
            status: MacosRunStatus.exited,
            readyForKeyCommands: false,
            reattached: false,
          ),
        );
      }
      await _persistence.clear();
      return;
    }

    _progress.emit(
      _progress.current.copyWith(
        status: MacosRunStatus.stopping,
        readyForKeyCommands: false,
        clearError: true,
      ),
    );

    if (_handle.hasLiveTools) {
      final tools = _handle.tools;
      final exitCode = await _handle.quit();
      if (tools != null) {
        await _settleExit(tools, exitCode, stoppedIntentionally: true);
      }
      await _progress.waitUntilNotStopping();
      return;
    }

    await _handle.quit();
    _liveness.cancel();
    await _persistence.clear();
    _progress.emit(
      _progress.current.copyWith(
        status: MacosRunStatus.exited,
        readyForKeyCommands: false,
        reattached: false,
        clearError: true,
      ),
    );
  }

  /// Detach without killing the app so a workbench hot restart can reclaim.
  Future<void> dispose() async {
    _disposed = true;
    _handle.invalidate();
    _liveness.cancel();
    await _handle.detachLeavingApp();
    await _progress.close();
  }

  void _adoptTools(MacosFlutterRun tools) {
    _handle.adopt(
      tools,
      onOutput: _onOutputChunk,
      onExit: (exitCode) {
        unawaited(_settleExit(tools, exitCode, stoppedIntentionally: false));
      },
    );
  }

  Future<void> _settleExit(
    MacosFlutterRun tools,
    int exitCode, {
    required bool stoppedIntentionally,
  }) async {
    if (!_handle.owns(tools)) return;
    _liveness.cancel();
    await _handle.releaseAfterExit(tools);

    if (!_disposed) {
      final wasStopping =
          stoppedIntentionally ||
          _progress.current.status == MacosRunStatus.stopping;
      final failed = exitCode != 0 && !wasStopping;
      _progress.emit(
        _progress.current.copyWith(
          status: failed ? MacosRunStatus.failed : MacosRunStatus.exited,
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
    if (!_handle.hasLiveTools || !_progress.current.readyForKeyCommands) {
      return;
    }
    try {
      await _handle.sendKey(key);
      _progress.appendLog('→ sent $key\n');
    } catch (error) {
      _progress.appendLog('Failed to send $key: $error\n');
    }
  }

  void _onOutputChunk(String chunk) {
    _progress.appendLog(chunk);
    final parsedUri =
        FlutterRunOutput.vmServiceUriFrom(chunk) ??
        FlutterRunOutput.vmServiceUriFrom(_progress.logText);
    if (parsedUri != null && parsedUri != _handle.vmServiceUri) {
      _handle.vmServiceUri = parsedUri;
      unawaited(
        _checkpoint(readyForKeyCommands: _progress.current.readyForKeyCommands),
      );
    }
    if (_progress.current.readyForKeyCommands) return;
    final status = _progress.current.status;
    if (status == MacosRunStatus.stopping ||
        status == MacosRunStatus.exited ||
        status == MacosRunStatus.failed) {
      return;
    }
    if (FlutterRunOutput.looksReady(chunk) ||
        FlutterRunOutput.looksReady(_progress.logText)) {
      _progress.emit(
        _progress.current.copyWith(
          status: MacosRunStatus.running,
          readyForKeyCommands: true,
          clearError: true,
        ),
      );
      unawaited(_checkpoint(readyForKeyCommands: true));
    }
  }

  Future<void> _checkpoint({required bool readyForKeyCommands}) async {
    final pid = _handle.trackedPid;
    final projectId = _progress.current.projectId;
    final projectName = _progress.current.projectName;
    final projectPath = _progress.current.projectPath;
    if (pid == null ||
        projectId == null ||
        projectName == null ||
        projectPath == null) {
      return;
    }
    await _persistence.write(
      MacosRunRecord(
        pid: pid,
        projectId: projectId,
        projectName: projectName,
        projectPath: projectPath,
        readyForKeyCommands: readyForKeyCommands,
        vmServiceUri: _handle.vmServiceUri,
      ),
    );
  }

  void _watchOrphanPid(int pid) {
    _liveness.watch(
      pid,
      onDead: () async {
        if (_handle.hasLiveTools || _disposed) return;
        if (_handle.trackedPid != pid) return;
        _handle.clearIdentity();
        await _persistence.clear();
        if (_progress.isActive) {
          _progress.appendLog('Reclaimed flutter run exited (pid $pid).\n');
          _progress.emit(
            _progress.current.copyWith(
              status: MacosRunStatus.exited,
              readyForKeyCommands: false,
              reattached: false,
            ),
          );
        }
      },
    );
  }
}
