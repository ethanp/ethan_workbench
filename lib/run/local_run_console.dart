import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';

import 'local_flutter_run.dart';
import 'local_flutter_run_binding.dart';
import 'local_run_checkpoint.dart';
import 'local_run_progress.dart';
import 'local_run_state.dart';

const _log = ELogger('LocalRunConsole');

/// Interprets `flutter run` console chunks into progress + binding updates.
class LocalRunConsole {
  LocalRunConsole({
    required this._runProgress,
    required this._flutterRunBinding,
    required this._checkpoint,
  });

  final LocalRunProgress _runProgress;
  final LocalFlutterRunBinding _flutterRunBinding;
  final LocalRunCheckpoint _checkpoint;

  /// Ignore EXCEPTION CAUGHT dumps at or before this log offset (hot reload /
  /// restart clear). Combined with restart banners inside [FlutterRunOutput].
  int _exceptionLogFloor = 0;

  void resetForNewRun() {
    _exceptionLogFloor = 0;
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
    binding.adopt(
      flutterRun,
      onOutput: _ingestFlutterRunOutput,
      onExit: onExit,
    );
  }

  void _ingestFlutterRunOutput(String chunk) {
    _runProgress.appendLog(chunk);
    _captureVmServiceUri(chunk);
    _captureFlutterException();
    _promoteToReadyIfNeeded(chunk);
  }

  void _captureVmServiceUri(String chunk) {
    final parsedUri =
        FlutterRunOutput.vmServiceUriFrom(chunk) ??
        FlutterRunOutput.vmServiceUriFrom(_runProgress.logText);
    if (parsedUri == null || parsedUri == _flutterRunBinding.vmServiceUri) {
      return;
    }
    _flutterRunBinding.vmServiceUri = parsedUri;
    unawaited(
      _checkpoint.write(
        readyForKeyCommands: _runProgress.current.readyForKeyCommands,
      ),
    );
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
      '${parsedException.displayLocation ?? ''}'.trim(),
    );
    _runProgress.emit(
      _runProgress.current.copyWith(flutterException: parsedException),
    );
  }

  void _promoteToReadyIfNeeded(String chunk) {
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
