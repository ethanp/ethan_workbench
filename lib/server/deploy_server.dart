import 'dart:async';

import 'package:shelf/shelf.dart';

import '../deploy/deploy_errors.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_pipeline.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_run_record.dart';
import '../deploy/deploy_session_persistence.dart';
import '../deploy/deploy_trigger.dart';
import '../projects/deployable_project.dart';
import '../projects/source_changes_progress.dart';
import '../run/local_run_registry.dart';
import '../sync/deploy_ledger.dart';
import 'deploy_http_server.dart';
import 'server_config.dart';

/// Mac façade: deploy workbench + LAN HTTP server for the iOS client.
class DeployServer({ServerConfig? config}) {
  this {
    _deployPipeline = DeployPipeline(
      flutterRoots: _config.flutterRoots,
      deployRbPath: _config.deployRbPath,
      persistence: DeploySessionPersistence(),
    );
    _localRunRegistry = MacLocalRunRegistry();
    _httpServer = DeployHttpServer(
      config: _config,
      deployPipeline: _deployPipeline,
      localRunRegistry: _localRunRegistry,
    );
  }

  final ServerConfig _config = config ?? ServerConfig();
  late final DeployPipeline _deployPipeline;
  late final DeployHttpServer _httpServer;
  late final MacLocalRunRegistry _localRunRegistry;

  ServerConfig get config => _config;
  DeployJob? get activeJob => _deployPipeline.activeJob;
  List<DeployJob> get waitingQueue => _deployPipeline.waitingQueue;
  Stream<DeployJob> get jobUpdates => _deployPipeline.jobUpdates;
  Stream<List<DeployJob>> get queueUpdates => _deployPipeline.queueUpdates;
  LocalRunRegistry get localRunRegistry => _localRunRegistry;
  bool get isRunning => _httpServer.isRunning;
  int? get boundPort => _httpServer.boundPort;

  /// In-process deploy UI trigger (iOS + macOS).
  DeployTrigger get localDeployTrigger => DeployTrigger(
    title: 'Deploy',
    showLineAgeAnalysis: true,
    flutterRoots: _config.flutterRoots,
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

  Handler buildHandler() => _httpServer.buildHandler();

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

  Future<void> start() => _httpServer.start();

  Future<void> stop() => _httpServer.stop();

  /// Reclaim a `flutter run` left alive across workbench hot restart.
  Future<void> restoreLocalRun() => _localRunRegistry.restorePersisted();

  /// Reclaim a deploy left running across workbench hot restart.
  Future<void> restoreDeploySession() =>
      _deployPipeline.restorePersistedSession();

  Future<void> dispose() async {
    await _localRunRegistry.dispose();
    await stop();
    await _deployPipeline.dispose();
  }
}
