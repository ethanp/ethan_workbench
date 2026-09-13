import 'dart:async';
import 'dart:convert';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../deploy/deploy_pipeline.dart';
import '../run/flutter_run_device.dart';
import '../run/local_run_controls.dart';
import '../run/local_run_key.dart';
import '../run/local_run_registry.dart';
import '../run/local_run_state.dart';
import 'deploy_http_sse.dart';
import 'json_http.dart';

const _log = ELogger('ServerJobEvents');

class const LocalRunTarget({
  required final LocalRunKey runKey,
  required final FlutterRunDevice device,
}) {
  factory fromBody(Map<String, dynamic> body) {
    final projectId = body['projectId'] as String?;
    final deviceKey = body['deviceKey'] as String?;
    if (projectId == null || projectId.isEmpty) {
      throw const FormatException('projectId is required');
    }
    if (deviceKey == null || deviceKey.isEmpty) {
      throw const FormatException('deviceKey is required');
    }
    final device = FlutterRunDevice.forKey(deviceKey);
    if (device == null) {
      throw const FormatException('deviceKey must be macos or meSim');
    }
    return LocalRunTarget(
      runKey: LocalRunKey(projectId: projectId, deviceKey: deviceKey),
      device: device,
    );
  }
}

class LocalRunHttpRoutes({
  required final LocalRunRegistry localRunRegistry,
  required final DeployPipeline deployPipeline,
}) {
  void mount(Router router) {
    router
      ..get('/runs', _listLocalRuns)
      ..get('/runs/log', _getLocalRunLog)
      ..get('/runs/events', _streamLocalRunEvents)
      ..post('/runs/start', _startLocalRun)
      ..post('/runs/stop', _stopLocalRun)
      ..post('/runs/hot-reload', _hotReloadLocalRun)
      ..post('/runs/hot-restart', _hotRestartLocalRun)
      ..post('/runs/full-restart', _fullRestartLocalRun);
  }

  Future<Response> _listLocalRuns(Request request) async {
    return jsonOk({
      'runs': [
        for (final runState in localRunRegistry.knownStates) runState.toJson(),
      ],
    });
  }

  Future<Response> _getLocalRunLog(Request request) async {
    final projectId = request.url.queryParameters['projectId'];
    final deviceKey = request.url.queryParameters['deviceKey'];
    if (projectId == null || projectId.isEmpty) {
      return jsonError('projectId is required', status: 400);
    }
    if (deviceKey == null || deviceKey.isEmpty) {
      return jsonError('deviceKey is required', status: 400);
    }
    final runState = localRunRegistry.stateFor(
      LocalRunKey(projectId: projectId, deviceKey: deviceKey),
    );
    return Response.ok(
      runState.log,
      headers: const {
        'Content-Type': 'text/plain; charset=utf-8',
        'Cache-Control': 'no-store',
      },
    );
  }

  FutureOr<Response> _streamLocalRunEvents(Request request) {
    final controller = StreamController<List<int>>();
    var emitCount = 0;
    String? lastSignature;

    void emit(LocalRunState runState) {
      if (controller.isClosed) return;
      emitCount += 1;
      final signature =
          '${runState.projectId}/${runState.deviceKey}:${runState.status.name}';
      if (signature != lastSignature || emitCount == 1) {
        _log.log(
          'run SSE emit #$emitCount ${runState.status.name} '
          'project=${runState.projectId} device=${runState.deviceKey} '
          'log=${runState.log.length}c',
        );
        lastSignature = signature;
      }
      controller.add(utf8.encode('data: ${jsonEncode(runState.toJson())}\n\n'));
    }

    _log.log(
      'run SSE subscriber open slots=${localRunRegistry.knownStates.length}',
    );
    for (final runState in localRunRegistry.knownStates) {
      emit(runState);
    }

    final subscription = localRunRegistry.stateUpdates.listen(
      emit,
      onError: (Object error, StackTrace stackTrace) {
        _log.warn('run SSE updates error', error, stackTrace);
        controller.addError(error, stackTrace);
      },
      onDone: () {
        _log.log('run SSE updates done emits=$emitCount');
        if (!controller.isClosed) {
          unawaited(controller.close());
        }
      },
    );

    controller.onCancel = () {
      _log.log('run SSE subscriber cancel emits=$emitCount');
      unawaited(subscription.cancel());
    };

    return Response.ok(
      controller.stream,
      headers: DeployHttpSse.headers,
      context: DeployHttpSse.context,
    );
  }

  Future<Response> _startLocalRun(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final target = LocalRunTarget.fromBody(body);
      final project = await deployPipeline.findProject(target.runKey.projectId);
      if (project == null) {
        return jsonError(
          'Unknown project: ${target.runKey.projectId}',
          status: 404,
        );
      }
      final controls = localRunRegistry.controlsFor(target.runKey);
      await controls.start(project, device: target.device);
      return jsonOk(controls.state.toJson());
    } on FormatException catch (error) {
      return jsonError(error.message, status: 400);
    } catch (error) {
      return jsonError(error.toString(), status: 500);
    }
  }

  Future<Response> _stopLocalRun(Request request) async {
    return _invokeLocalRunCommand(request, (controls) => controls.stop());
  }

  Future<Response> _hotReloadLocalRun(Request request) async {
    return _invokeLocalRunCommand(request, (controls) => controls.hotReload());
  }

  Future<Response> _hotRestartLocalRun(Request request) async {
    return _invokeLocalRunCommand(request, (controls) => controls.hotRestart());
  }

  Future<Response> _fullRestartLocalRun(Request request) async {
    return _invokeLocalRunCommand(request, (controls) => controls.fullRestart());
  }

  Future<Response> _invokeLocalRunCommand(
    Request request,
    Future<void> Function(LocalRunControls controls) invoke,
  ) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final target = LocalRunTarget.fromBody(body);
      final controls = localRunRegistry.controlsFor(target.runKey);
      await invoke(controls);
      return jsonOk(controls.state.toJson());
    } on FormatException catch (error) {
      return jsonError(error.message, status: 400);
    } catch (error) {
      return jsonError(error.toString(), status: 500);
    }
  }
}
