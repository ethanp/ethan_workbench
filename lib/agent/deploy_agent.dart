import 'dart:async';

import 'package:shelf/shelf.dart';

import '../deploy/deploy_errors.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_pipeline.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_run_record.dart';
import '../deploy/deploy_session_persistence.dart';
import '../deploy/deploy_trigger.dart';
import '../pairing/pairing_auth.dart';
import '../projects/deployable_project.dart';
import '../projects/source_changes_progress.dart';
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
    _deployPipeline = DeployPipeline(
      flutterRoots: _config.flutterRoots,
      deployRbPath: _config.deployRbPath,
      persistence: DeploySessionPersistence(),
    );
    _localRun = LocalRunSession(
      isDeployBlocking: () {
        final job = _deployPipeline.activeJob;
        return job != null && job.status.isActiveRunner;
      },
      deployBlockMessage: () {
        final job = _deployPipeline.activeJob;
        return job?.projectName;
      },
    );
    _server = DeployAgentServer(
      config: _config,
      pairingAuth: _pairingAuth,
      deployPipeline: _deployPipeline,
      localRun: _localRun,
    );
  }

  final AgentConfig _config;
  final PairingAuth _pairingAuth;
  late final DeployPipeline _deployPipeline;
  late final DeployAgentServer _server;
  late final LocalRunSession _localRun;

  AgentConfig get config => _config;
  PairingAuth get pairingAuth => _pairingAuth;
  DeployJob? get activeJob => _deployPipeline.activeJob;
  List<DeployJob> get waitingQueue => _deployPipeline.waitingQueue;
  Stream<DeployJob> get jobUpdates => _deployPipeline.jobUpdates;
  Stream<List<DeployJob>> get queueUpdates => _deployPipeline.queueUpdates;
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
    fetchActiveJob: () async {
      final job = activeJob;
      if (job == null || job.status.isTerminal) return null;
      return job;
    },
    listDeployHistory: listDeployHistory,
    fetchDeployQueue: () async => waitingQueue,
    cancelQueuedDeploy: cancelQueuedDeploy,
    jobUpdates: jobUpdates,
    queueUpdates: queueUpdates,
  );

  Handler buildHandler() => _server.buildHandler();

  Future<List<DeployableProject>> listProjects() =>
      _deployPipeline.listProjects();

  Future<List<DeployableProject>> evaluateSourceChanges({
    void Function(SourceChangesProgress progress)? onProgress,
  }) {
    return _deployPipeline.evaluateSourceChanges(onProgress: onProgress);
  }

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
    return _deployPipeline.startDeploy(
      projectId: projectId,
      platform: platform,
      force: force,
    );
  }

  Future<DeployJob> fetchJob(String jobId) => _deployPipeline.fetchJob(jobId);

  Future<List<DeployRunRecord>> listDeployHistory() =>
      _deployPipeline.listRecentRuns();

  Future<void> cancelQueuedDeploy(String jobId) async {
    if (!_deployPipeline.cancelWaiting(jobId)) {
      throw DeployJobNotFound(jobId);
    }
  }

  void attachLedger(DeployLedger ledger) {
    _deployPipeline.attachLedger(ledger);
  }

  Future<void> start() async {
    await _pairingAuth.restorePersistedSessions();
    await _server.start();
  }

  Future<void> stop() => _server.stop();

  /// Reclaim a `flutter run` left alive across workbench hot restart.
  Future<void> restoreLocalRun() => _localRun.restorePersisted();

  /// Reclaim a deploy left running across workbench hot restart.
  Future<void> restoreDeploySession() =>
      _deployPipeline.restorePersistedSession();

  /// Reload paired phone sessions from disk (also runs inside [start]).
  Future<void> restorePairedSessions() =>
      _pairingAuth.restorePersistedSessions();

  Future<void> dispose() async {
    await _localRun.dispose();
    await stop();
    await _deployPipeline.dispose();
    await _pairingAuth.dispose();
  }
}
