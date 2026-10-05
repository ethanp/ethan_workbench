import 'flutter_run_device.dart';
import 'local_flutter_run.dart';
import 'local_flutter_run_binding.dart';
import 'local_run_checkpoint.dart';
import 'local_run_console.dart';
import 'local_run_key.dart';
import 'local_run_persistence.dart';
import 'local_run_progress.dart';
import 'local_run_state.dart';
import 'os_process_tree.dart';
import 'simulator_vm_service_log.dart';
import 'vm_service_endpoint.dart';

/// Reclaims a `flutter run` left alive across workbench hot restart.
class LocalRunReclaimer({
  required final LocalRunKey _runKey,
  required final LocalRunProgress _runProgress,
  required final LocalFlutterRunBinding _flutterRunBinding,
  required final LocalRunPersistence _persistence,
  required final LocalRunCheckpoint _checkpoint,
  required final LocalRunConsole _console,
  required final void Function(LocalFlutterRun flutterRun) _adoptFlutterRun,
  required final bool Function() _isDisposed,
}) {
  final _liveness = PidLivenessWatch();
  final _simulatorVmServiceLog = const SimulatorVmServiceLog();

  void cancelLiveness() => _liveness.cancel();

  Future<void> restorePersisted() async {
    if (_isDisposed() || _runProgress.isActive) return;
    final record = await _persistence.read(_runKey);
    if (record == null) return;

    final attachTarget = await _attachTargetFor(record);
    if (attachTarget == null) {
      await _persistence.clear(_runKey);
      return;
    }

    _flutterRunBinding.trackedPid = attachTarget.orphanPid;
    if (record.deviceKey == FlutterRunDevice.meSim.key) {
      _flutterRunBinding.deviceVmServiceUri = attachTarget.vmServiceUri;
    } else {
      _flutterRunBinding.vmServiceUri = attachTarget.vmServiceUri;
    }
    _runProgress.clearLog();
    _console.resetForNewRun();
    _runProgress.appendLog(attachTarget.reclaimLog);
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

    await _attachAndAdopt(record, attachTarget);
  }

  Future<void> _attachAndAdopt(
    LocalRunRecord record,
    _ReclaimAttachTarget attachTarget,
  ) async {
    try {
      final flutterRun = await _flutterRunBinding.attachToRunning(
        projectPath: record.projectPath,
        deviceId: record.flutterDeviceId,
        vmServiceUri: attachTarget.vmServiceUri,
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
      await _keepOrphanOrGiveUp(attachTarget, error);
    }
  }

  Future<_ReclaimAttachTarget?> _attachTargetFor(LocalRunRecord record) async {
    final hostEndpoint = VmServiceEndpoint(record.vmServiceUri);
    final hostListening = await hostEndpoint.isListening;
    var orphanPid = await record.pid.asOsProcessTree.isAlive
        ? record.pid
        : null;
    if (orphanPid != null && hostEndpoint.isPresent && !hostListening) {
      await orphanPid.asOsProcessTree.killTillExit();
      orphanPid = null;
    }

    final String? attachUri = await _debugUriForAttach(
      record,
      hostListening: hostListening,
    );
    if (attachUri == null && orphanPid == null) return null;
    final attachingToAppOnSimulator =
        record.deviceKey == FlutterRunDevice.meSim.key &&
        attachUri != null &&
        attachUri != record.vmServiceUri;
    return _ReclaimAttachTarget(
      orphanPid: orphanPid,
      vmServiceUri: attachUri,
      reclaimLog: _reclaimLog(
        deviceLabel: record.deviceLabel,
        orphanPid: orphanPid,
        attachingToAppOnSimulator: attachingToAppOnSimulator,
      ),
    );
  }

  /// `--debug-url` for a simulator must be the app's "listening on" port.
  /// The host "available at" URL is a forward that died with `flutter run`;
  /// passing it makes attach forward the wrong device port and retry forever.
  /// macOS has no forwarder, so the host URL is the service itself.
  Future<String?> _debugUriForAttach(
    LocalRunRecord record, {
    required bool hostListening,
  }) async {
    if (record.deviceKey == FlutterRunDevice.meSim.key) {
      final String? savedDeviceUri = record.deviceVmServiceUri;
      if (savedDeviceUri != null && savedDeviceUri.isNotEmpty) {
        return savedDeviceUri;
      }
      return _simulatorVmServiceLog.latestListeningUri(record.flutterDeviceId);
    }
    if (hostListening) return record.vmServiceUri;
    return null;
  }

  String _reclaimLog({
    required String deviceLabel,
    required int? orphanPid,
    required bool attachingToAppOnSimulator,
  }) {
    final String pidNote = orphanPid == null ? '' : ' (pid $orphanPid)';
    final String attachNote = attachingToAppOnSimulator
        ? 'Saved VM service was the old host forward. '
              'Attaching to the app still running on $deviceLabel…\n'
        : 'Attaching for hot reload…\n';
    return 'Reclaimed session after workbench restart$pidNote.\n$attachNote';
  }

  Future<void> _keepOrphanOrGiveUp(
    _ReclaimAttachTarget attachTarget,
    Object error,
  ) async {
    final orphanPid = attachTarget.orphanPid;
    if (orphanPid != null) {
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
      watchOrphanPid(orphanPid);
      return;
    }
    await _persistence.clear(_runKey);
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

  void watchOrphanPid(int pid) {
    _liveness.watch(
      pid,
      onDead: () async {
        if (_flutterRunBinding.hasFlutterRun || _isDisposed()) return;
        if (_flutterRunBinding.trackedPid != pid) return;
        _flutterRunBinding.clearIdentity();
        await _persistence.clear(_runKey);
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

class const _ReclaimAttachTarget({
  required final int? orphanPid,
  required final String? vmServiceUri,
  required final String reclaimLog,
});
