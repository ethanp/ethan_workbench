import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';

import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_queue.dart';
import '../deploy/deploy_run_record.dart';
import '../deploy/deploy_trigger.dart';
import '../phone/deploy_http_client.dart';
import '../projects/source_changes_progress.dart';
import '../projects/workbench_project.dart';
import '../run/local_run_registry.dart';
import '../run/remote_local_run_registry.dart';
import 'server_endpoint.dart';

const _log = ELogger('WorkbenchLanSession');

/// HTTP client session against a running [DeployServer] (daemon or companion).
class WorkbenchLanSession({
  required final DeployServerClient deployServerClient,
  final String? unreachableHint,
}) {
  this {
    _localRunRegistry = RemoteLocalRunRegistry(server: deployServerClient);
  }

  final _jobUpdatesController = StreamController<DeployJob>.broadcast();
  late final RemoteLocalRunRegistry _localRunRegistry;

  bool _listening = false;
  bool _jobEventsLoopRunning = false;
  Future<void> Function()? _onUnauthorized;

  Stream<DeployJob> get jobUpdates => _jobUpdatesController.stream;

  LocalRunRegistry get localRunRegistry => _localRunRegistry;

  DeployTrigger deployTrigger({
    Future<void> Function()? onUnauthorized,
    Future<void> Function()? onSignOut,
    bool showSignOut = false,
    bool showLineAgeAnalysis = false,
    List<String> flutterRoots = const [],
  }) {
    _onUnauthorized = onUnauthorized;
    _localRunRegistry.setOnUnauthorized(onUnauthorized);

    return DeployTrigger(
      title: 'Deploy',
      showSignOut: showSignOut,
      showLineAgeAnalysis: showLineAgeAnalysis,
      flutterRoots: flutterRoots,
      preferredPlatforms: const [DeployPlatform.macos, DeployPlatform.ios],
      unreachableHint:
          unreachableHint ??
          'Is the workbench daemon running at $loopbackServerBaseUrl?',
      listProjects: listProjects,
      evaluateSourceChanges: evaluateSourceChanges,
      startDeploy: startDeploy,
      fetchJob: fetchJob,
      fetchActiveJob: fetchActiveJob,
      listDeployHistory: listDeployHistory,
      fetchDeployQueue: fetchDeployQueue,
      cancelQueuedDeploy: cancelQueuedDeploy,
      reorderQueuedDeploy: reorderQueuedDeploy,
      jobUpdates: jobUpdates,
      onUnauthorized: onUnauthorized,
      onSignOut: onSignOut,
    );
  }

  void startListening() {
    if (_listening) return;
    _listening = true;
    _ensureJobEventsListening();
    _localRunRegistry.startListening();
  }

  void stopListening() {
    _listening = false;
    _localRunRegistry.stopListening();
    deployServerClient.cancelJobEvents();
  }

  Future<List<WorkbenchProject>> listProjects() =>
      deployServerClient.listProjects();

  Future<List<WorkbenchProject>> evaluateSourceChanges({
    void Function(SourceChangesProgress progress)? onProgress,
  }) {
    return deployServerClient.evaluateSourceChanges();
  }

  Future<DeployJob> startDeploy({
    required String projectId,
    required DeployPlatform platform,
    bool force = false,
  }) {
    return deployServerClient.startDeploy(
      projectId: projectId,
      platform: platform,
      force: force,
    );
  }

  Future<DeployJob> fetchJob(String jobId) => deployServerClient.fetchJob(jobId);

  Future<DeployJob?> fetchActiveJob() => deployServerClient.fetchActiveJob();

  Future<List<DeployRunRecord>> listDeployHistory() =>
      deployServerClient.listDeployHistory();

  Future<DeployQueue> fetchDeployQueue() =>
      deployServerClient.fetchDeployQueue();

  Future<void> cancelQueuedDeploy(String jobId) =>
      deployServerClient.cancelQueuedDeploy(jobId);

  Future<void> reorderQueuedDeploy({
    required String jobId,
    required int toIndex,
  }) {
    return deployServerClient.reorderQueuedDeploy(
      jobId: jobId,
      toIndex: toIndex,
    );
  }

  void _ensureJobEventsListening() {
    if (_jobEventsLoopRunning) {
      _log.log('job-events loop already running listening=$_listening');
      return;
    }
    _jobEventsLoopRunning = true;
    _log.log('starting job-events loop');
    unawaited(_runJobEventsLoop());
  }

  Future<void> _runJobEventsLoop() async {
    var connectAttempt = 0;
    try {
      while (_listening) {
        connectAttempt += 1;
        var eventCount = 0;
        String? lastStatus;
        String? lastChecklist;
        _log.log('SSE connect attempt=$connectAttempt');
        try {
          await for (final job in deployServerClient.watchJobEvents()) {
            if (!_listening) break;
            eventCount += 1;
            final checklistSignature = job.checklist
                .map((item) => '${item.id}:${item.status.name}')
                .join(',');
            final noteworthy =
                job.status.name != lastStatus ||
                checklistSignature != lastChecklist ||
                eventCount == 1 ||
                eventCount % 25 == 0;
            if (noteworthy) {
              _log.log(
                'SSE event #$eventCount hasListeners='
                '${_jobUpdatesController.hasListener} ${job.debugSummary}',
              );
              lastStatus = job.status.name;
              lastChecklist = checklistSignature;
            }
            if (!_jobUpdatesController.isClosed) {
              _jobUpdatesController.add(job);
            }
          }
          _log.warn(
            'SSE stream ended attempt=$connectAttempt events=$eventCount '
            'listening=$_listening',
          );
        } on ServerRequestException catch (error) {
          _log.warn(
            'SSE ServerRequestException attempt=$connectAttempt '
            'status=${error.statusCode} ${error.message}',
          );
          if (error.isUnauthorized) {
            final onUnauthorized = _onUnauthorized;
            if (onUnauthorized != null) {
              await onUnauthorized();
            }
            break;
          }
        } catch (error, stackTrace) {
          _log.warn(
            'SSE error attempt=$connectAttempt — reconnecting',
            error,
            stackTrace,
          );
        }
        if (!_listening) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } finally {
      _jobEventsLoopRunning = false;
      _log.log('job-events loop stopped listening=$_listening');
    }
  }

  void close() {
    stopListening();
    unawaited(_localRunRegistry.close());
    unawaited(_jobUpdatesController.close());
    deployServerClient.close();
  }
}
