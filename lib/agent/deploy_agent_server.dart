import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../deploy/deploy_errors.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_service.dart';
import '../pairing/auth_middleware.dart';
import '../pairing/pairing_auth.dart';
import 'agent_config.dart';
import 'json_http.dart';
import 'request_logging.dart';

/// Shelf HTTP surface for pairing, project list, and deploys.
class DeployAgentServer {
  DeployAgentServer({
    required this.config,
    required this.pairingAuth,
    required this.deployService,
  });

  final AgentConfig config;
  final PairingAuth pairingAuth;
  final DeployService deployService;
  HttpServer? _httpServer;

  bool get isRunning => _httpServer != null;
  int? get boundPort => _httpServer?.port;

  Handler buildHandler() {
    final router = Router()
      ..get('/health', _health)
      ..post('/pair', _pair)
      ..get('/projects', _listProjects)
      ..post('/projects/evaluate-changes', _evaluateSourceChanges)
      ..post('/deploy', _startDeploy)
      ..get('/jobs/active', _activeJob)
      ..get('/jobs/<jobId>', _getJob)
      ..get('/jobs/<jobId>/log', _streamLog);

    return Pipeline()
        .addMiddleware(quietRequestLog())
        .addMiddleware(pairingAuthMiddleware(pairingAuth))
        .addHandler(router.call);
  }

  Future<void> start() async {
    if (_httpServer != null) return;
    pairingAuth.ensureFreshPin();
    _httpServer = await shelf_io.serve(
      buildHandler(),
      InternetAddress.anyIPv4,
      config.port,
    );
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

  Future<Response> _getJob(Request request, String jobId) async {
    final job = deployService.activeJob;
    if (job == null || job.jobId != jobId) {
      return jsonError('Job not found', status: 404);
    }
    return jsonOk(job.toJson());
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
      return '$escaped\n\n';
    });

    return Response.ok(
      transformed,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      },
    );
  }
}
