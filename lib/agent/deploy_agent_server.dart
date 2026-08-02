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
import '../deploy/deploy_service.dart';
import '../pairing/auth_middleware.dart';
import '../pairing/pairing_auth.dart';
import '../run/flutter_run_device.dart';
import '../run/local_run_session.dart';
import '../run/local_run_state.dart';
import 'agent_config.dart';
import 'json_http.dart';
import 'request_logging.dart';

const _log = ELogger('AgentJobEvents');

/// Shelf HTTP surface for pairing, project list, deploys, and local runs.
class DeployAgentServer {
  DeployAgentServer({
    required this.config,
    required this.pairingAuth,
    required this.deployService,
    required this.localRun,
  });

  final AgentConfig config;
  final PairingAuth pairingAuth;
  final DeployService deployService;
  final LocalRunSession localRun;
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
      ..post('/pair', _pair)
      ..get('/projects', _listProjects)
      ..post('/projects/evaluate-changes', _evaluateSourceChanges)
      ..post('/deploy', _startDeploy)
      ..get('/jobs/history', _listHistory)
      ..get('/jobs/active', _activeJob)
      ..get('/jobs/events', _streamJobEvents)
      ..get('/jobs/<jobId>', _getJob)
      ..get('/jobs/<jobId>/log', _streamLog)
      ..get('/run', _getLocalRun)
      ..get('/run/events', _streamLocalRunEvents)
      ..post('/run', _startLocalRun)
      ..post('/run/stop', _stopLocalRun)
      ..post('/run/hot-reload', _hotReloadLocalRun)
      ..post('/run/hot-restart', _hotRestartLocalRun)
      ..post('/run/full-restart', _fullRestartLocalRun);

    return Pipeline()
        .addMiddleware(quietRequestLog())
        .addMiddleware(pairingAuthMiddleware(pairingAuth))
        .addHandler(router.call);
  }

  Future<void> start() async {
    if (_httpServer != null) return;
    pairingAuth.ensureFreshPin();
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
      throw TimeoutException('Timed out binding agent port ${config.port}');
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
      'activeJobId': deployService.activeJob?.jobId,
      'localRunActive': localRun.isActive,
      'pairedSessions': pairingAuth.sessionCount,
    });
  }

  Future<Response> _pair(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final pin = body['pin'] as String?;
      if (pin == null || pin.trim().isEmpty) {
        return jsonError('pin is required', status: 400);
      }
      final label = body['label'] as String? ?? 'iPhone';
      final token = pairingAuth.pair(pin, label: label);
      if (token == null) {
        return jsonError('Invalid or expired PIN', status: 403);
      }
      return jsonOk({'token': token});
    } catch (error) {
      return jsonError(error.toString(), status: 400);
    }
  }

  Future<Response> _listProjects(Request request) async {
    final projects = await deployService.listProjects();
    return jsonOk({
      'projects': projects.map((project) => project.toJson()).toList(),
    });
  }

  Future<Response> _evaluateSourceChanges(Request request) async {
    final projects = await deployService.evaluateSourceChanges();
    return jsonOk({
      'projects': projects.map((project) => project.toJson()).toList(),
    });
  }

  Future<Response> _startDeploy(Request request) async {
    try {
      if (localRun.isActive) {
        throw LocalRunBlocksDeploy(
          projectName: localRun.state.projectName ?? 'local run',
          statusName: localRun.state.status.name,
        );
      }
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
      final job = await deployService.startDeploy(
        projectId: projectId,
        platform: DeployPlatform.fromName(platformName),
        force: force,
      );
      return jsonOk(job.toJson());
    } on DeployAlreadyRunning catch (error) {
      final job = error.job;
      return jsonError(
        error.toString(),
        status: 409,
        extra: job == null ? null : {'job': job.toJson()},
      );
    } on LocalRunBlocksDeploy catch (error) {
      return jsonError(error.toString(), status: 409);
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

  Future<Response> _activeJob(Request request) async {
    final job = deployService.activeJob;
    if (job == null) {
      return jsonError('No active job', status: 404);
    }
    return jsonOk(job.toJson());
  }

  Future<Response> _listHistory(Request request) async {
    final runs = await deployService.listRecentRuns();
    return jsonOk({'runs': runs.map((run) => run.toJson()).toList()});
  }

  Future<Response> _getJob(Request request, String jobId) async {
    final job = deployService.activeJob;
    if (job == null || job.jobId != jobId) {
      return jsonError('Job not found', status: 404);
    }
    return jsonOk(job.toJson());
  }

  FutureOr<Response> _streamJobEvents(Request request) {
    final controller = StreamController<List<int>>();
    var emitCount = 0;
    String? lastStatus;
    String? lastChecklist;

    void emit(DeployJob job) {
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

    final activeJob = deployService.activeJob;
    _log.log(
      'SSE subscriber open active='
      '${activeJob?.debugSummary ?? 'none'}',
    );
    if (activeJob != null) {
      emit(activeJob);
    }

    final subscription = deployService.jobUpdates.listen(
      emit,
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

    controller.onCancel = () {
      _log.log('SSE subscriber cancel emits=$emitCount');
      unawaited(subscription.cancel());
    };

    return Response.ok(
      controller.stream,
      headers: _sseHeaders,
      context: _sseContext,
    );
  }

  FutureOr<Response> _streamLog(Request request, String jobId) {
    final job = deployService.activeJob;
    if (job == null || job.jobId != jobId) {
      return jsonError('Job not found', status: 404);
    }

    final logStream = deployService.watchLog(jobId);
    final transformed = logStream.map((chunk) {
      final escaped = chunk
          .replaceAll('\r', '')
          .split('\n')
          .map((line) => 'data: $line')
          .join('\n');
      return utf8.encode('$escaped\n\n');
    });

    return Response.ok(
      transformed,
      headers: _sseHeaders,
      context: _sseContext,
    );
  }

  Future<Response> _getLocalRun(Request request) async {
    return jsonOk(localRun.state.toJson());
  }

  FutureOr<Response> _streamLocalRunEvents(Request request) {
    final controller = StreamController<List<int>>();
    var emitCount = 0;
    String? lastStatus;

    void emit(LocalRunState runState) {
      if (controller.isClosed) return;
      emitCount += 1;
      if (runState.status.name != lastStatus || emitCount == 1) {
        _log.log(
          'run SSE emit #$emitCount ${runState.status.name} '
          'project=${runState.projectId} device=${runState.deviceKey} '
          'log=${runState.log.length}c',
        );
        lastStatus = runState.status.name;
      }
      controller.add(utf8.encode('data: ${jsonEncode(runState.toJson())}\n\n'));
    }

    _log.log(
      'run SSE subscriber open '
      '${localRun.state.status.name} project=${localRun.state.projectId}',
    );
    emit(localRun.state);

    final subscription = localRun.updates.listen(
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
      final projectId = body['projectId'] as String?;
      final deviceKey = body['deviceKey'] as String?;
      if (projectId == null || projectId.isEmpty) {
        return jsonError('projectId is required', status: 400);
      }
      if (deviceKey == null || deviceKey.isEmpty) {
        return jsonError('deviceKey is required', status: 400);
      }
      final device = FlutterRunDevice.forKey(deviceKey);
      if (device == null) {
        return jsonError('deviceKey must be macos or meSim', status: 400);
      }
      final project = await deployService.findProject(projectId);
      if (project == null) {
        return jsonError('Unknown project: $projectId', status: 404);
      }
      await localRun.start(project, device: device);
      return jsonOk(localRun.state.toJson());
    } on LocalRunAlreadyActive catch (error) {
      return jsonError(
        error.toString(),
        status: 409,
        extra: {'run': localRun.state.toJson()},
      );
    } on DeployBlocksLocalRun catch (error) {
      return jsonError(error.toString(), status: 409);
    } catch (error) {
      return jsonError(error.toString(), status: 500);
    }
  }

  Future<Response> _stopLocalRun(Request request) async {
    try {
      await localRun.stop();
      return jsonOk(localRun.state.toJson());
    } catch (error) {
      return jsonError(error.toString(), status: 500);
    }
  }

  Future<Response> _hotReloadLocalRun(Request request) async {
    try {
      await localRun.hotReload();
      return jsonOk(localRun.state.toJson());
    } catch (error) {
      return jsonError(error.toString(), status: 500);
    }
  }

  Future<Response> _hotRestartLocalRun(Request request) async {
    try {
      await localRun.hotRestart();
      return jsonOk(localRun.state.toJson());
    } catch (error) {
      return jsonError(error.toString(), status: 500);
    }
  }

  Future<Response> _fullRestartLocalRun(Request request) async {
    try {
      await localRun.fullRestart();
      return jsonOk(localRun.state.toJson());
    } catch (error) {
      return jsonError(error.toString(), status: 500);
    }
  }
}
