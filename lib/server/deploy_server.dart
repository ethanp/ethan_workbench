import 'dart:async';

import 'package:shelf/shelf.dart';

import 'daemon_restart_after_queue.dart';
import '../deploy/deploy_errors.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_pipeline.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_queue.dart';
import '../deploy/deploy_run_record.dart';
import '../deploy/deploy_session_persistence.dart';
import '../deploy/deploy_trigger.dart';
import '../projects/source_changes_progress.dart';
import '../projects/workbench_project.dart';
import '../run/local_run_registry.dart';
import '../sync/deploy_ledger.dart';
import 'deploy_http_server.dart';
import 'server_config.dart';

/// Mac façade: deploy workbench + LAN HTTP server for the iOS client.
class DeployServer({ServerConfig? config, this.onExitRequested}) {
  this {
    _deployPipeline = DeployPipeline(
      flutterRoots: _config.flutterRoots,
      deployRbPath: _config.deployRbPath,
      persistence: DeploySessionPersistence(),
      onBecameIdle: () => _restartAfterQueue?.becameIdle(),
    );
    final restartAfterQueue = DaemonRestartAfterQueue(
      isIdle: () => _deployPipeline.isIdle,
      restartDaemon: _exitAfterHttpResponse,
    );
    _restartAfterQueue = restartAfterQueue;
    _localRunRegistry = MacLocalRunRegistry();
    _httpServer = DeployHttpServer(
      config: _config,
      deployPipeline: _deployPipeline,
      localRunRegistry: _localRunRegistry,
      restartAfterQueue: restartAfterQueue,
    );
  }

  final ServerConfig _config = config ?? ServerConfig();
  final void Function()? onExitRequested;
  DaemonRestartAfterQueue? _restartAfterQueue;
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
    fetchDeployQueue: fetchDeployQueue,
    cancelQueuedDeploy: cancelQueuedDeploy,
    reorderQueuedDeploy: reorderQueuedDeploy,
    jobUpdates: jobUpdates,
    queueUpdates: queueUpdates,
  );

  Handler buildHandler() => _httpServer.buildHandler();

  Future<List<WorkbenchProject>> listProjects() =>
      _deployPipeline.listProjects();

  Future<List<WorkbenchProject>> evaluateSourceChanges({
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

  Future<DeployQueue> fetchDeployQueue() async => DeployQueue(
    waiting: waitingQueue,
    restartAfterQueue: restartAfterQueueScheduled,
  );

  Future<void> cancelQueuedDeploy(String jobId) async {
    if (!_deployPipeline.cancelWaiting(jobId)) {
      throw DeployJobNotFound(jobId);
    }
  }

  Future<void> reorderQueuedDeploy({
    required String jobId,
    required int toIndex,
  }) async {
    if (!_deployPipeline.moveWaitingJob(jobId: jobId, toIndex: toIndex)) {
      throw DeployJobNotFound(jobId);
    }
  }

  void attachLedger(DeployLedger ledger) {
    _deployPipeline.attachLedger(ledger);
  }

  bool get restartAfterQueueScheduled =>
      _restartAfterQueue?.scheduled ?? false;

  /// Arm a restart once the deploy queue and active run are idle.
  bool enqueueRestartAfterQueue() {
    final restartAfterQueue = _restartAfterQueue;
    if (restartAfterQueue == null) return false;
    return restartAfterQueue.enqueue();
  }

  void _exitAfterHttpResponse() {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        onExitRequested?.call();
      }),
    );
  }

  Future<void> start({bool takeOverOccupiedPort = false}) =>
      _httpServer.start(takeOverOccupiedPort: takeOverOccupiedPort);

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
