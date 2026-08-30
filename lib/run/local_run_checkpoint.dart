import 'local_flutter_run_binding.dart';
import 'local_run_key.dart';
import 'local_run_persistence.dart';
import 'local_run_progress.dart';

/// Writes / clears the on-disk local-run reclaim record.
class LocalRunCheckpoint({
  required final LocalRunKey _runKey,
  required final LocalRunProgress _runProgress,
  required final LocalFlutterRunBinding _flutterRunBinding,
  required final LocalRunPersistence _persistence,
}) {
  Future<void> write({required bool readyForKeyCommands}) async {
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
      _runKey,
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

  Future<void> clear() => _persistence.clear(_runKey);
}
