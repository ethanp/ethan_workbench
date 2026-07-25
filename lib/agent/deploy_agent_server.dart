import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'agent_config.dart';
import 'deploy_job_runner.dart';
import 'pairing_auth.dart';

class DeployAgentServer {
  factory DeployAgentServer({AgentConfig? config}) {
    final resolvedConfig = config ?? AgentConfig();
    return DeployAgentServer._(resolvedConfig);
  }

  DeployAgentServer._(this._config)
      : _jobRunner = DeployJobRunner(config: _config),
        _pairingAuth = PairingAuth();

  final AgentConfig _config;
  final DeployJobRunner _jobRunner;
  final PairingAuth _pairingAuth;
  HttpServer? _httpServer;

  AgentConfig get config => _config;
  DeployJobRunner get jobRunner => _jobRunner;
  PairingAuth get pairingAuth => _pairingAuth;
  bool get isRunning => _httpServer != null;
  int? get boundPort => _httpServer?.port;

  Handler buildHandler() {
    final router = Router()
      ..get('/health', _health)
      ..post('/pair', _pair)
      ..get('/projects', _listProjects)
      ..post('/deploy', _startDeploy)
      ..get('/jobs/active', _activeJob)
      ..get('/jobs/<jobId>', _getJob)
      ..get('/jobs/<jobId>/log', _streamLog);

    return Pipeline()
        .addMiddleware(_quietRequestLog)
        .addMiddleware(_authMiddleware)
        .addHandler(router.call);
  }

  Middleware get _authMiddleware {
    return (Handler innerHandler) {
      return (Request request) {
        final path = request.requestedUri.path;
        if (path == '/health' || path == '/pair') {
          return innerHandler(request);
        }
        final authorization = request.headers['authorization'];
        final token = authorization?.startsWith('Bearer ') == true
            ? authorization!.substring('Bearer '.length).trim()
            : null;
        if (!_pairingAuth.isAuthorized(token)) {
          return Response.unauthorized(
            jsonEncode({'error': 'Unauthorized — pair with the PIN on the Mac'}),
            headers: _jsonHeaders,
          );
        }
        return innerHandler(request);
      };
    };
  }

  /// Logs meaningful traffic; skips noisy job/health polls from the phone UI.
  static Middleware get _quietRequestLog {
    return (Handler innerHandler) {
      return (Request request) async {
        final startedAt = DateTime.now();
        final response = await innerHandler(request);
        if (_shouldLogRequest(request, response)) {
          final elapsed = DateTime.now().difference(startedAt);
          // ignore: avoid_print — companion console feedback for deploy actions
          print(
            '${startedAt.toIso8601String()}  '
            '${elapsed.toString().padLeft(15)} '
            '${request.method.padRight(7)} '
            '[${response.statusCode}] '
            '${request.requestedUri.path}',
          );
        }
        return response;
      };
    };
  }

  static bool _shouldLogRequest(Request request, Response response) {
    if (response.statusCode >= 400) return true;
    final path = request.requestedUri.path;
    if (request.method == 'GET' && path == '/health') return false;
    if (request.method == 'GET' && path.startsWith('/jobs/')) return false;
    return true;
  }

  Future<void> start() async {
    if (_httpServer != null) return;
    _pairingAuth.ensureFreshPin();
    _httpServer = await shelf_io.serve(
      buildHandler(),
      InternetAddress.anyIPv4,
      _config.port,
    );
  }

  Future<void> stop() async {
    final server = _httpServer;
    _httpServer = null;
    await server?.close(force: true);
  }

  Future<void> dispose() async {
    await stop();
    await _jobRunner.dispose();
    await _pairingAuth.dispose();
  }

  Future<Response> _health(Request request) async {
    return Response.ok(
      jsonEncode({
        'ok': true,
        'activeJobId': _jobRunner.activeJob?.jobId,
        'pairedSessions': _pairingAuth.sessionCount,
      }),
      headers: _jsonHeaders,
    );
  }

  Future<Response> _pair(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final pin = body['pin'] as String?;
      if (pin == null || pin.trim().isEmpty) {
        return _error('pin is required', status: 400);
      }
      final label = body['label'] as String? ?? 'iPhone';
      final token = _pairingAuth.pair(pin, label: label);
      if (token == null) {
        return _error('Invalid or expired PIN', status: 403);
      }
      return Response.ok(
        jsonEncode({'token': token}),
        headers: _jsonHeaders,
      );
    } catch (error) {
      return _error(error.toString(), status: 400);
    }
  }

  Future<Response> _listProjects(Request request) async {
    final projects = await _jobRunner.listProjects();
    return Response.ok(
      jsonEncode({
        'projects': projects.map((project) => project.toJson()).toList(),
      }),
      headers: _jsonHeaders,
    );
  }

  Future<Response> _startDeploy(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final projectId = body['projectId'] as String?;
      if (projectId == null || projectId.isEmpty) {
        return _error('projectId is required', status: 400);
      }
      final force = body['force'] as bool? ?? false;
      final job = await _jobRunner.startDeploy(
        projectId: projectId,
        force: force,
      );
      return Response.ok(jsonEncode(job.toJson()), headers: _jsonHeaders);
    } on StateError catch (error) {
      return _error(error.message, status: 409);
    } on ArgumentError catch (error) {
      return _error('${error.message}', status: 404);
    } catch (error) {
      return _error(error.toString(), status: 500);
    }
  }

  Future<Response> _activeJob(Request request) async {
    final job = _jobRunner.activeJob;
    if (job == null) {
      return Response.notFound(
        jsonEncode({'error': 'No active job'}),
        headers: _jsonHeaders,
      );
    }
    return Response.ok(jsonEncode(job.toJson()), headers: _jsonHeaders);
  }

  Future<Response> _getJob(Request request, String jobId) async {
    final job = _jobRunner.activeJob;
    if (job == null || job.jobId != jobId) {
      return Response.notFound(
        jsonEncode({'error': 'Job not found'}),
        headers: _jsonHeaders,
      );
    }
    return Response.ok(jsonEncode(job.toJson()), headers: _jsonHeaders);
  }

  FutureOr<Response> _streamLog(Request request, String jobId) {
    final job = _jobRunner.activeJob;
    if (job == null || job.jobId != jobId) {
      return Response.notFound(
        jsonEncode({'error': 'Job not found'}),
        headers: _jsonHeaders,
      );
    }

    final logStream = _jobRunner.watchLog(jobId);
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

  Response _error(String message, {required int status}) {
    return Response(
      status,
      body: jsonEncode({'error': message}),
      headers: _jsonHeaders,
    );
  }

  static const _jsonHeaders = {'Content-Type': 'application/json'};
}

Future<String?> firstLanIpv4Address() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLinkLocal: false,
  );
  for (final networkInterface in interfaces) {
    for (final address in networkInterface.addresses) {
      if (address.isLoopback) continue;
      return address.address;
    }
  }
  return null;
}
