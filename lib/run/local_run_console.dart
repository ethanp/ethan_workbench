import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';

import 'local_flutter_run.dart';
import 'local_flutter_run_binding.dart';
import 'local_run_checkpoint.dart';
import 'local_run_progress.dart';
import 'local_run_state.dart';

const _log = ELogger('LocalRunConsole');

/// Interprets `flutter run` console chunks into progress + binding updates.
class LocalRunConsole({
  required final LocalRunProgress _runProgress,
  required final LocalFlutterRunBinding _flutterRunBinding,
  required final LocalRunCheckpoint _checkpoint,
  final void Function()? onAttachGaveUpOnVmService,
}) {
  /// Ignore EXCEPTION CAUGHT dumps at or before this log offset (hot reload /
  /// restart clear). Combined with restart banners inside [FlutterRunOutput].
  int _exceptionLogFloor = 0;
  bool _reportedAttachGaveUp = false;

  void resetForNewRun() {
    _exceptionLogFloor = 0;
    _reportedAttachGaveUp = false;
  }

  /// Advance the exception floor past the current log (hot reload / restart).
  void clearFlutterException() {
    _exceptionLogFloor = _runProgress.logText.length;
    if (_runProgress.current.flutterException == null) return;
    _runProgress.emit(
      _runProgress.current.copyWith(clearFlutterException: true),
    );
  }

  void bindFlutterRunOutput(
    LocalFlutterRunBinding binding,
    LocalFlutterRun flutterRun, {
    required void Function(int exitCode) onExit,
  }) {
    binding.adopt(flutterRun, onOutput: _interpretConsoleChunk, onExit: onExit);
  }

  void _interpretConsoleChunk(String chunk) {
    _runProgress.appendLog(chunk);
    _captureVmServiceUri(chunk);
    _captureDeviceVmServiceUri(chunk);
    _captureFlutterException();
    _markReadyWhenKeyCommandsAppear(chunk);
    _stopAttachThatCannotReachVmService(chunk);
  }

  void _captureVmServiceUri(String chunk) {
    final parsedUri =
        FlutterRunOutput.vmServiceUriFrom(chunk) ??
        FlutterRunOutput.vmServiceUriFrom(_runProgress.logText);
    if (parsedUri == null || parsedUri == _flutterRunBinding.vmServiceUri) {
      return;
    }
    _flutterRunBinding.vmServiceUri = parsedUri;
    _checkpointReady();
  }

  void _captureDeviceVmServiceUri(String chunk) {
    final String? parsedUri =
        FlutterRunOutput.deviceVmServiceUriFrom(chunk) ??
        FlutterRunOutput.deviceVmServiceUriFrom(_runProgress.logText);
    if (parsedUri == null ||
        parsedUri == _flutterRunBinding.deviceVmServiceUri) {
      return;
    }
    _flutterRunBinding.deviceVmServiceUri = parsedUri;
    _checkpointReady();
  }

  void _checkpointReady() {
    unawaited(
      _checkpoint.write(
        readyForKeyCommands: _runProgress.current.readyForKeyCommands,
      ),
    );
  }

  void _stopAttachThatCannotReachVmService(String chunk) {
    if (_reportedAttachGaveUp) return;
    if (_runProgress.current.readyForKeyCommands) return;
    if (!_runProgress.current.reattached) return;
    if (!FlutterRunOutput.attachGaveUpOnVmService(chunk) &&
        !FlutterRunOutput.attachGaveUpOnVmService(_runProgress.logText)) {
      return;
    }
    _reportedAttachGaveUp = true;
    onAttachGaveUpOnVmService?.call();
  }

  void _captureFlutterException() {
    final parsedException = FlutterRunOutput.exceptionFrom(
      _runProgress.logText,
      floor: _exceptionLogFloor,
    );
    final scanStart = FlutterRunOutput.exceptionScanStart(
      _runProgress.logText,
      floor: _exceptionLogFloor,
    );
    if (scanStart > _exceptionLogFloor) {
      _exceptionLogFloor = scanStart;
      if (_runProgress.current.flutterException != null &&
          parsedException == null) {
        _runProgress.emit(
          _runProgress.current.copyWith(clearFlutterException: true),
        );
      }
    }
    if (parsedException == null ||
        !parsedException.isRicherThan(_runProgress.current.flutterException)) {
      return;
    }
    _log.warn(
      'Flutter exception '
              '${parsedException.widget ?? parsedException.library ?? 'unknown'} '
              '${parsedException.displayLocation ?? ''}'
          .trim(),
    );
    _runProgress.emit(
      _runProgress.current.copyWith(flutterException: parsedException),
    );
  }

  void _markReadyWhenKeyCommandsAppear(String chunk) {
    if (_runProgress.current.readyForKeyCommands) return;
    final status = _runProgress.current.status;
    if (status == LocalRunStatus.stopping ||
        status == LocalRunStatus.exited ||
        status == LocalRunStatus.failed) {
      return;
    }
    if (!FlutterRunOutput.looksReady(chunk) &&
        !FlutterRunOutput.looksReady(_runProgress.logText)) {
      return;
    }
    _runProgress.emit(
      _runProgress.current.copyWith(
        status: LocalRunStatus.running,
        readyForKeyCommands: true,
        clearError: true,
      ),
    );
    unawaited(_checkpoint.write(readyForKeyCommands: true));
  }
}
