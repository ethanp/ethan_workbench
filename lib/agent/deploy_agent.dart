import 'dart:async';

import 'package:shelf/shelf.dart';

import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_run_record.dart';
import '../deploy/deploy_service.dart';
import '../deploy/deploy_trigger.dart';
import '../pairing/pairing_auth.dart';
import '../projects/deployable_project.dart';
import '../run/local_run_session.dart';
import '../run/local_run_state.dart';
import '../sync/deploy_ledger.dart';
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
    _localRun = LocalRunSession(
      isDeployBlocking: () {
        final job = _deployService.activeJob;
        return job != null && !job.status.isTerminal;
      },
      deployBlockMessage: () {
        final job = _deployService.activeJob;
        return job?.projectName;
      },
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
  late final LocalRunSession _localRun;

  AgentConfig get config => _config;
  PairingAuth get pairingAuth => _pairingAuth;
  DeployJob? get activeJob => _deployService.activeJob;
  Stream<DeployJob> get jobUpdates => _deployService.jobUpdates;
  LocalRunSession get localRun => _localRun;
  bool get isRunning => _server.isRunning;
  int? get boundPort => _server.boundPort;

  /// In-process deploy UI trigger (iOS + macOS).
  DeployTrigger get localDeployTrigger => DeployTrigger(
    title: 'Deploy',
    showLineAgeAnalysis: true,
    preferredPlatforms: const [DeployPlatform.macos, DeployPlatform.ios],
    listProjects: listProjects,
    evaluateSourceChanges: evaluateSourceChanges,
    startDeploy: startDeploy,
    fetchJob: fetchJob,
    fetchActiveJob: () async => activeJob,
    listDeployHistory: listDeployHistory,
    jobUpdates: jobUpdates,
  );

  Handler buildHandler() => _server.buildHandler();

  Future<List<DeployableProject>> listProjects() =>
      _deployService.listProjects();

  Future<List<DeployableProject>> evaluateSourceChanges() =>
      _deployService.evaluateSourceChanges();

  Future<DeployJob> startDeploy({
    required String projectId,
    required DeployPlatform platform,
    bool force = false,
  }) {
    if (_localRun.isActive) {
      throw LocalRunBlocksDeploy(
        projectName: _localRun.state.projectName ?? 'local run',
        statusName: _localRun.state.status.name,
      );
    }
    return _deployService.startDeploy(
      projectId: projectId,
      platform: platform,
      force: force,
    );
  }

  Future<DeployJob> fetchJob(String jobId) => _deployService.fetchJob(jobId);

  Future<List<DeployRunRecord>> listDeployHistory() =>
      _deployService.listRecentRuns();

  void attachLedger(DeployLedger ledger) {
    _deployService.attachLedger(ledger);
  }

  Future<void> start() async {
    await _pairingAuth.restorePersistedSessions();
    await _server.start();
  }

  Future<void> stop() => _server.stop();

  /// Reclaim a `flutter run` left alive across workbench hot restart.
  Future<void> restoreLocalRun() => _localRun.restorePersisted();

  /// Reload paired phone sessions from disk (also runs inside [start]).
  Future<void> restorePairedSessions() =>
      _pairingAuth.restorePersistedSessions();

  Future<void> dispose() async {
    await _localRun.dispose();
    await stop();
    await _deployService.dispose();
    await _pairingAuth.dispose();
  }
}
