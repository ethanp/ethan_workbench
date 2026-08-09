import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';

import '../phone/deploy_http_client.dart';
import '../projects/deployable_project.dart';
import 'flutter_run_device.dart';
import 'local_run_controls.dart';
import 'local_run_state.dart';

const _log = ELogger('RemoteLocalRun');

/// Phone-side proxy: drives Mac [LocalRunSession] over the LAN server.
class RemoteLocalRunSession implements LocalRunControls {
  RemoteLocalRunSession({required this.server, this.onUnauthorized});

  final DeployServerClient server;
  Future<void> Function()? onUnauthorized;

  final _updatesController = StreamController<LocalRunState>.broadcast();
  LocalRunState _state = LocalRunState.idle;
  bool _listening = false;
  bool _closed = false;
  bool _wantListening = false;
  Timer? _pollTimer;

  @override
  LocalRunState get state => _state;

  @override
  Stream<LocalRunState> get updates => _updatesController.stream;

  @override
  bool get isActive => _state.status.isActive;

  void setOnUnauthorized(Future<void> Function()? callback) {
    onUnauthorized = callback;
  }

  void startListening() {
    if (_closed) return;
    _wantListening = true;
    _ensureListening();
    _pollTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_pullSnapshot(reason: 'poll')),
    );
    unawaited(_pullSnapshot(reason: 'start'));
  }

  void stopListening() {
    _wantListening = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    server.cancelRunEvents();
  }

  void _ensureListening() {
    if (_listening || !_wantListening || _closed) return;
    _listening = true;
    unawaited(_runEventsLoop());
  }

  Future<void> _runEventsLoop() async {
    var connectAttempt = 0;
    try {
      while (_wantListening && !_closed) {
        connectAttempt += 1;
        var eventCount = 0;
        LocalRunStatus? lastStatus;
        _log.log('SSE connect attempt=$connectAttempt');
        try {
          await for (final runState in server.watchLocalRunEvents()) {
            if (!_wantListening || _closed) break;
            eventCount += 1;
            if (runState.status != lastStatus || eventCount == 1) {
              _log.log(
                'SSE event #$eventCount ${runState.status.name} '
                'project=${runState.projectId} device=${runState.deviceKey} '
                'hasListeners=${_updatesController.hasListener}',
              );
              lastStatus = runState.status;
            }
            _publish(runState);
          }
          _log.warn(
            'SSE stream ended attempt=$connectAttempt events=$eventCount',
          );
        } on ServerRequestException catch (error) {
          _log.warn(
            'SSE ServerRequestException attempt=$connectAttempt '
            'status=${error.statusCode} ${error.message}',
          );
          if (error.isUnauthorized) {
            final callback = onUnauthorized;
            if (callback != null) await callback();
            break;
          }
        } catch (error, stackTrace) {
          _log.warn(
            'SSE error attempt=$connectAttempt — reconnecting',
            error,
            stackTrace,
          );
        }
        if (!_wantListening || _closed) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } finally {
      _listening = false;
      _log.log('SSE loop stopped want=$_wantListening');
      if (_wantListening && !_closed) {
        _ensureListening();
      }
    }
  }

  Future<void> _pullSnapshot({required String reason}) async {
    if (_closed || !_wantListening) return;
    try {
      final runState = await server.fetchLocalRun();
      if (runState.status != _state.status ||
          runState.projectId != _state.projectId ||
          runState.deviceKey != _state.deviceKey ||
          reason == 'start') {
        _log.log(
          '$reason snapshot ${runState.status.name} '
          'project=${runState.projectId} device=${runState.deviceKey}',
        );
      }
      _publish(runState);
    } on ServerRequestException catch (error) {
      if (error.isUnauthorized) {
        _log.warn('snapshot unauthorized');
        final callback = onUnauthorized;
        if (callback != null) await callback();
        return;
      }
      _log.warn('snapshot failed: ${error.message}');
    } catch (error, stackTrace) {
      _log.warn('snapshot failed', error, stackTrace);
    }
  }

  void _publish(LocalRunState runState) {
    _state = runState;
    if (!_updatesController.isClosed) {
      _updatesController.add(runState);
    }
  }

  @override
  Future<void> start(
    DeployableProject project, {
    required FlutterRunDevice device,
  }) async {
    final runState = await server.startLocalRun(
      projectId: project.projectId,
      deviceKey: device.key,
    );
    _publish(runState);
  }

  @override
  Future<void> stop() async {
    final runState = await server.stopLocalRun();
    _publish(runState);
  }

  @override
  Future<void> hotReload() async {
    final runState = await server.hotReloadLocalRun();
    _publish(runState);
  }

  @override
  Future<void> hotRestart() async {
    final runState = await server.hotRestartLocalRun();
    _publish(runState);
  }

  @override
  Future<void> fullRestart() async {
    final runState = await server.fullRestartLocalRun();
    _publish(runState);
  }

  Future<void> close() async {
    _closed = true;
    _wantListening = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    server.cancelRunEvents();
    await _updatesController.close();
  }
}
