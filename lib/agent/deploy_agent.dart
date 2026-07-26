import 'dart:async';

import 'package:shelf/shelf.dart';

import '../deploy/deploy_job.dart';
import '../deploy/deploy_service.dart';
import '../pairing/pairing_auth.dart';
import 'agent_config.dart';
import 'deploy_agent_server.dart';

/// Mac companion façade: pairing desk + deploy workbench + LAN HTTP agent.
class DeployAgent {
  DeployAgent({AgentConfig? config})
      : _config = config ?? AgentConfig(),
        _pairingAuth = PairingAuth() {
    _deployService = DeployService(
      flutterRoots: _config.flutterRoots,
      deployRbPath: _config.deployRbPath,
    );
    _server = DeployAgentServer(
      config: _config,
      pairingAuth: _pairingAuth,
      deployService: _deployService,
    );
  }

  final AgentConfig _config;
  final PairingAuth _pairingAuth;
  late final DeployService _deployService;
  late final DeployAgentServer _server;

  AgentConfig get config => _config;
  PairingAuth get pairingAuth => _pairingAuth;
  DeployJob? get activeJob => _deployService.activeJob;
  Stream<DeployJob> get jobUpdates => _deployService.jobUpdates;
  bool get isRunning => _server.isRunning;
  int? get boundPort => _server.boundPort;

  Handler buildHandler() => _server.buildHandler();

  Future<void> start() => _server.start();

  Future<void> stop() => _server.stop();

  Future<void> dispose() async {
    await stop();
    await _deployService.dispose();
    await _pairingAuth.dispose();
  }
}
