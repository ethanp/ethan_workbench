import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../deploy/deploy_errors.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_pipeline.dart';
import '../run/flutter_run_device.dart';
import '../run/local_run_controls.dart';
import '../run/local_run_key.dart';
import '../run/local_run_registry.dart';
import '../run/local_run_state.dart';
import 'json_http.dart';
import 'password_auth_middleware.dart';
import 'request_logging.dart';
import 'server_config.dart';

const _log = ELogger('ServerJobEvents');

/// Shelf HTTP surface for the iOS client: projects, deploys, and local runs.
class DeployHttpServer({
  required final ServerConfig config,
  required final DeployPipeline deployPipeline,
  required final LocalRunRegistry localRunRegistry,
}) {
  HttpServer? _httpServer;

  static const _sseHeaders = {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  };

  /// shelf_io buffers streamed bodies by default; that stalls SSE on the phone.
  static const _sseContext = {'shelf.io.buffer_output': false};

  bool get isRunning => _httpServer != null;
  int? get boundPort => _httpServer?.port;

  Handler buildHandler() {
    final router = Router()
      ..get('/health', _health)
      ..get('/projects', _listProjects)
      ..post('/projects/evaluate-changes', _evaluateSourceChanges)
      ..post('/deploy', _startDeploy)
      ..get('/deploy/queue', _listDeployQueue)
      ..delete('/deploy/queue/<jobId>', _cancelQueuedDeploy)
      ..get('/jobs/history', _listHistory)
      ..get('/jobs/active', _activeJob)
      ..get('/jobs/events', _streamJobEvents)
      ..get('/jobs/<jobId>', _getJob)
      ..get('/jobs/<jobId>/log', _streamLog)
      ..get('/runs', _listLocalRuns)
      ..get('/runs/log', _getLocalRunLog)
      ..get('/runs/events', _streamLocalRunEvents)
      ..post('/runs/start', _startLocalRun)
      ..post('/runs/stop', _stopLocalRun)
      ..post('/runs/hot-reload', _hotReloadLocalRun)
      ..post('/runs/hot-restart', _hotRestartLocalRun)
      ..post('/runs/full-restart', _fullRestartLocalRun);

    return Pipeline()
        .addMiddleware(quietRequestLog())
        .addMiddleware(passwordAuthMiddleware())
        .addHandler(router.call);
  }

  Future<void> start() async {
    if (_httpServer != null) return;
    try {
      _httpServer = await shelf_io
          .serve(
            buildHandler(),
            InternetAddress.anyIPv4,
            config.port,
            shared: true,
          )
          .timeout(const Duration(seconds: 5));
    } on TimeoutException {
      throw TimeoutException('Timed out binding server port ${config.port}');
    }
  }

  Future<void> stop() async {
    final server = _httpServer;
    _httpServer = null;
    await server?.close(force: true);
  }

  Future<Response> _health(Request request) async {
    return jsonOk({
      'ok': true,
      'activeJobId': deployPipeline.activeJob?.jobId,
      'activeLocalRunCount': localRunRegistry.activeCount,
    });
  }

  Future<Response> _listProjects(Request request) async {
    final projects = await deployPipeline.listProjects();
    return jsonOk({
      'projects': projects.map((project) => project.toJson()).toList(),
    });
  }

  Future<Response> _evaluateSourceChanges(Request request) async {
    final projects = await deployPipeline.evaluateSourceChanges();
    return jsonOk({
      'projects': projects.map((project) => project.toJson()).toList(),
    });
  }

  Future<Response> _startDeploy(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final projectId = body['projectId'] as String?;
      if (projectId == null || projectId.isEmpty) {
        return jsonError('projectId is required', status: 400);
      }
      final force = body['force'] as bool? ?? false;
      final platformName =
          body['platform'] as String? ?? DeployPlatform.ios.name;
      if (platformName != DeployPlatform.ios.name &&
          platformName != DeployPlatform.macos.name) {
        return jsonError('platform must be ios or macos', status: 400);
      }
      final job = await deployPipeline.startDeploy(
        projectId: projectId,
        platform: DeployPlatform.fromName(platformName),
        force: force,
      );
      return jsonOk(job.toJson());
    } on DeployAlreadyQueued catch (error) {
      return jsonError(
        error.toString(),
        status: 409,
        extra: {'job': error.job.toJson(), 'alreadyQueued': true},
      );
    } on UnknownProject catch (error) {
      return jsonError(error.toString(), status: 404);
    } on UnsupportedDeployPlatform catch (error) {
      return jsonError(error.toString(), status: 400);
    } on DeployScriptMissing catch (error) {
      return jsonError(error.toString(), status: 500);
    } catch (error) {
      return jsonError(error.toString(), status: 500);
    }
  }

  Future<Response> _listDeployQueue(Request request) async {
    return jsonOk({
      'jobs': deployPipeline.waitingQueue.map((job) => job.toJson()).toList(),
    });
  }

  Future<Response> _cancelQueuedDeploy(Request request, String jobId) async {
    if (!deployPipeline.cancelWaiting(jobId)) {
      return jsonError('Queued job not found', status: 404);
    }
    return jsonOk({'ok': true});
  }

  Future<Response> _activeJob(Request request) async {
    final job = deployPipeline.activeJob;
    if (job == null || job.status.isTerminal) {
      return jsonError('No active job', status: 404);
    }
    return jsonOk(job.toJson());
  }

  Future<Response> _listHistory(Request request) async {
    final runs = await deployPipeline.listRecentRuns();
    return jsonOk({'runs': runs.map((run) => run.toJson()).toList()});
  }

  Future<Response> _getJob(Request request, String jobId) async {
    try {
      final job = await deployPipeline.fetchJob(jobId);
      return jsonOk(job.toJson());
    } on DeployJobNotFound {
      return jsonError('Job not found', status: 404);
    }
  }

  FutureOr<Response> _streamJobEvents(Request request) {
    final controller = StreamController<List<int>>();
    var emitCount = 0;
    String? lastStatus;
    String? lastChecklist;

    void emitJob(DeployJob job) {
      if (controller.isClosed) return;
      emitCount += 1;
      final checklistSignature = job.checklist
          .map((item) => '${item.id}:${item.status.name}')
          .join(',');
      final noteworthy =
          job.status.name != lastStatus ||
          checklistSignature != lastChecklist ||
          emitCount == 1 ||
          emitCount % 25 == 0;
      if (noteworthy) {
        _log.log('SSE emit #$emitCount ${job.debugSummary}');
        lastStatus = job.status.name;
        lastChecklist = checklistSignature;
      }
      controller.add(utf8.encode('data: ${jsonEncode(job.toJson())}\n\n'));
    }

    void emitQueue(List<DeployJob> jobs) {
      if (controller.isClosed) return;
      controller.add(
        utf8.encode(
          'data: ${jsonEncode({'type': 'queue', 'jobs': jobs.map((job) => job.toJson()).toList()})}\n\n',
        ),
      );
    }

    final activeJob = deployPipeline.activeJob;
    _log.log(
      'SSE subscriber open active='
      '${activeJob?.debugSummary ?? 'none'}',
    );
    if (activeJob != null && !activeJob.status.isTerminal) {
      emitJob(activeJob);
    }
    emitQueue(deployPipeline.waitingQueue);

    final jobSubscription = deployPipeline.jobUpdates.listen(
      emitJob,
      onError: (Object error, StackTrace stackTrace) {
        _log.warn('SSE jobUpdates error', error, stackTrace);
        controller.addError(error, stackTrace);
      },
      onDone: () {
        _log.log('SSE jobUpdates done emits=$emitCount');
        if (!controller.isClosed) {
          unawaited(controller.close());
        }
      },
    );
    final queueSubscription = deployPipeline.queueUpdates.listen(emitQueue);

    controller.onCancel = () {
      _log.log('SSE subscriber cancel emits=$emitCount');
      unawaited(jobSubscription.cancel());
      unawaited(queueSubscription.cancel());
    };

    return Response.ok(
      controller.stream,
      headers: _sseHeaders,
      context: _sseContext,
    );
  }

  FutureOr<Response> _streamLog(Request request, String jobId) {
    final job = deployPipeline.activeJob;
    if (job == null || job.jobId != jobId) {
      return jsonError('Job not found', status: 404);
    }

    final logStream = deployPipeline.watchLog(jobId);
    final transformed = logStream.map((chunk) {
      final escaped = chunk
          .replaceAll('\r', '')
          .split('\n')
          .map((line) => 'data: $line')
          .join('\n');
      return utf8.encode('$escaped\n\n');
    });

    return Response.ok(transformed, headers: _sseHeaders, context: _sseContext);
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
      headers: _sseHeaders,
      context: _sseContext,
    );
  }

  Future<Response> _startLocalRun(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final target = _localRunTargetFromBody(body);
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
    return _mutateLocalRun(request, (controls) => controls.stop());
  }

  Future<Response> _hotReloadLocalRun(Request request) async {
    return _mutateLocalRun(request, (controls) => controls.hotReload());
  }

  Future<Response> _hotRestartLocalRun(Request request) async {
    return _mutateLocalRun(request, (controls) => controls.hotRestart());
  }

  Future<Response> _fullRestartLocalRun(Request request) async {
    return _mutateLocalRun(request, (controls) => controls.fullRestart());
  }

  Future<Response> _mutateLocalRun(
    Request request,
    Future<void> Function(LocalRunControls controls) mutate,
  ) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final target = _localRunTargetFromBody(body);
      final controls = localRunRegistry.controlsFor(target.runKey);
      await mutate(controls);
      return jsonOk(controls.state.toJson());
    } on FormatException catch (error) {
      return jsonError(error.message, status: 400);
    } catch (error) {
      return jsonError(error.toString(), status: 500);
    }
  }

  _LocalRunTarget _localRunTargetFromBody(Map<String, dynamic> body) {
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
    return _LocalRunTarget(
      runKey: LocalRunKey(projectId: projectId, deviceKey: deviceKey),
      device: device,
    );
  }
}

class const _LocalRunTarget({
  required final LocalRunKey runKey,
  required final FlutterRunDevice device,
});
