import 'dart:async';

import '../phone/deploy_http_client.dart';
import '../projects/deployable_project.dart';
import 'flutter_run_device.dart';
import 'local_run_controls.dart';
import 'local_run_state.dart';

/// Phone-side proxy: drives Mac [LocalRunSession] over the LAN agent.
class RemoteLocalRunSession implements LocalRunControls {
  RemoteLocalRunSession({required this.agent, this.onUnauthorized});

  final MacAgentClient agent;
  Future<void> Function()? onUnauthorized;

  final _updatesController = StreamController<LocalRunState>.broadcast();
  LocalRunState _state = LocalRunState.idle;
  bool _listening = false;
  bool _closed = false;
  bool _wantListening = false;

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
  }

  void stopListening() {
    _wantListening = false;
    agent.cancelRunEvents();
  }

  void _ensureListening() {
    if (_listening || !_wantListening || _closed) return;
    _listening = true;
    unawaited(_runEventsLoop());
  }

  Future<void> _runEventsLoop() async {
    try {
      while (_wantListening && !_closed) {
        try {
          await for (final runState in agent.watchLocalRunEvents()) {
            if (!_wantListening || _closed) break;
            _publish(runState);
          }
        } on AgentRequestException catch (error) {
          if (error.isUnauthorized) {
            final callback = onUnauthorized;
            if (callback != null) await callback();
            break;
          }
        } catch (_) {
          // Reconnect below while still wanted.
        }
        if (!_wantListening || _closed) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } finally {
      _listening = false;
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
    final runState = await agent.startLocalRun(
      projectId: project.projectId,
      deviceKey: device.key,
    );
    _publish(runState);
  }

  @override
  Future<void> stop() async {
    final runState = await agent.stopLocalRun();
    _publish(runState);
  }

  @override
  Future<void> hotReload() async {
    final runState = await agent.hotReloadLocalRun();
    _publish(runState);
  }

  @override
  Future<void> hotRestart() async {
    final runState = await agent.hotRestartLocalRun();
    _publish(runState);
  }

  @override
  Future<void> fullRestart() async {
    final runState = await agent.fullRestartLocalRun();
    _publish(runState);
  }

  Future<void> close() async {
    _closed = true;
    _wantListening = false;
    agent.cancelRunEvents();
    await _updatesController.close();
  }
}
