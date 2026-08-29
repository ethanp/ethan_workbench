import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';

import '../phone/deploy_http_client.dart';
import '../projects/deployable_project.dart';
import 'flutter_run_device.dart';
import 'local_run_controls.dart';
import 'local_run_key.dart';
import 'local_run_registry.dart';
import 'local_run_state.dart';

const _log = ELogger('RemoteLocalRun');

/// Phone-side proxy: drives Mac [MacLocalRunRegistry] over the LAN server.
class RemoteLocalRunRegistry implements LocalRunRegistry {
  RemoteLocalRunRegistry({required this.server, this.onUnauthorized});

  final DeployServerClient server;
  Future<void> Function()? onUnauthorized;

  final Map<LocalRunKey, LocalRunState> _states = {};
  final Map<LocalRunKey, RemoteLocalRunSlot> _slots = {};
  final _changes = StreamController<void>.broadcast();
  final _stateUpdates = StreamController<LocalRunState>.broadcast();
  bool _listening = false;
  bool _closed = false;
  bool _wantListening = false;
  Timer? _pollTimer;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Stream<LocalRunState> get stateUpdates => _stateUpdates.stream;

  @override
  List<LocalRunState> get knownStates => _states.values.toList();

  @override
  int get activeCount =>
      _states.values.where((runState) => runState.status.isActive).length;

  @override
  LocalRunState stateFor(LocalRunKey runKey) =>
      _states[runKey] ?? LocalRunState.idle;

  @override
  LocalRunControls controlsFor(LocalRunKey runKey) {
    return _slots.putIfAbsent(
      runKey,
      () => RemoteLocalRunSlot(remoteRunRegistry: this, runKey: runKey),
    );
  }

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
        String? lastSignature;
        _log.log('SSE connect attempt=$connectAttempt');
        try {
          await for (final runState in server.watchLocalRunEvents()) {
            if (!_wantListening || _closed) break;
            eventCount += 1;
            final signature =
                '${runState.projectId}/${runState.deviceKey}:${runState.status.name}';
            if (signature != lastSignature || eventCount == 1) {
              _log.log(
                'SSE event #$eventCount ${runState.status.name} '
                'project=${runState.projectId} device=${runState.deviceKey} '
                'hasListeners=${_changes.hasListener}',
              );
              lastSignature = signature;
            }
            adopt(runState);
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
      final runStates = await server.fetchLocalRuns();
      _log.log('$reason snapshot count=${runStates.length}');
      for (final runState in runStates) {
        adopt(runState);
      }
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

  void adopt(LocalRunState runState) {
    final runKey = runState.runKey;
    if (runKey == null) return;
    _states[runKey] = runState;
    if (!_changes.isClosed) {
      _changes.add(null);
    }
    if (!_stateUpdates.isClosed) {
      _stateUpdates.add(runState);
    }
  }

  Future<void> close() async {
    _closed = true;
    _wantListening = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    server.cancelRunEvents();
    await _changes.close();
    await _stateUpdates.close();
  }
}

class RemoteLocalRunSlot implements LocalRunControls {
  RemoteLocalRunSlot({
    required this.remoteRunRegistry,
    required this.runKey,
  });

  final RemoteLocalRunRegistry remoteRunRegistry;
  final LocalRunKey runKey;

  @override
  LocalRunState get state => remoteRunRegistry.stateFor(runKey);

  @override
  Stream<LocalRunState> get updates => remoteRunRegistry.stateUpdates.where(
    (runState) =>
        runState.projectId == runKey.projectId &&
        runState.deviceKey == runKey.deviceKey,
  );

  @override
  bool get isActive => state.status.isActive;

  @override
  Future<void> start(
    DeployableProject project, {
    required FlutterRunDevice device,
  }) async {
    final runState = await remoteRunRegistry.server.startLocalRun(
      projectId: project.projectId,
      deviceKey: device.key,
    );
    remoteRunRegistry.adopt(runState);
  }

  @override
  Future<void> stop() async {
    final runState = await remoteRunRegistry.server.stopLocalRun(
      projectId: runKey.projectId,
      deviceKey: runKey.deviceKey,
    );
    remoteRunRegistry.adopt(runState);
  }

  @override
  Future<void> hotReload() async {
    final runState = await remoteRunRegistry.server.hotReloadLocalRun(
      projectId: runKey.projectId,
      deviceKey: runKey.deviceKey,
    );
    remoteRunRegistry.adopt(runState);
  }

  @override
  Future<void> hotRestart() async {
    final runState = await remoteRunRegistry.server.hotRestartLocalRun(
      projectId: runKey.projectId,
      deviceKey: runKey.deviceKey,
    );
    remoteRunRegistry.adopt(runState);
  }

  @override
  Future<void> fullRestart() async {
    final runState = await remoteRunRegistry.server.fullRestartLocalRun(
      projectId: runKey.projectId,
      deviceKey: runKey.deviceKey,
    );
    remoteRunRegistry.adopt(runState);
  }
}
