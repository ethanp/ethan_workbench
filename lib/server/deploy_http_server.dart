import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../deploy/deploy_pipeline.dart';
import '../run/local_run_registry.dart';
import 'deploy_http_routes.dart';
import 'json_http.dart';
import 'listening_tcp_port.dart';
import 'local_run_http_routes.dart';
import 'password_auth_middleware.dart';
import 'request_logging.dart';
import 'server_config.dart';

/// Shelf HTTP surface for the iOS client: projects, deploys, and local runs.
class DeployHttpServer({
  required final ServerConfig config,
  required final DeployPipeline deployPipeline,
  required final LocalRunRegistry localRunRegistry,
}) {
  HttpServer? _httpServer;

  bool get isRunning => _httpServer != null;
  int? get boundPort => _httpServer?.port;

  Handler buildHandler() {
    final router = Router()..get('/health', _health);
    DeployHttpRoutes(deployPipeline: deployPipeline).mount(router);
    LocalRunHttpRoutes(
      localRunRegistry: localRunRegistry,
      deployPipeline: deployPipeline,
    ).mount(router);

    return Pipeline()
        .addMiddleware(quietRequestLog())
        .addMiddleware(passwordAuthMiddleware())
        .addHandler(router.call);
  }

  Future<void> start({bool takeOverOccupiedPort = false}) async {
    if (_httpServer != null) return;
    try {
      await _bindHttp();
    } on SocketException catch (error) {
      if (!error.isAddressInUse) rethrow;
      if (!takeOverOccupiedPort) rethrow;
      await config.port.asListeningTcpPort.killOtherListenersTillExit();
      await _bindHttp();
    }
  }

  Future<void> _bindHttp() async {
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
}
