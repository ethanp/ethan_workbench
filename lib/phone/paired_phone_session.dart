import 'dart:async';
import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';

import '../agent/agent_endpoint.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_run_record.dart';
import '../deploy/deploy_trigger.dart';
import '../pairing/session_token_store.dart';
import '../projects/deployable_project.dart';
import '../projects/source_changes_progress.dart';
import '../run/local_run_controls.dart';
import '../run/remote_local_run_session.dart';
import 'deploy_http_client.dart';

const _log = ELogger('PhoneJobEvents');

/// Phone-side session: restore pairing, talk to the Mac agent, unpair on revoke.
class PairedPhoneSession {
  PairedPhoneSession({
    MacAgentClient? agentClient,
    SessionTokenStore? tokenStore,
  }) : _agent = agentClient ?? MacAgentClient(),
       _tokenStore = tokenStore ?? SessionTokenStore() {
    _localRun = RemoteLocalRunSession(agent: _agent);
  }

  final MacAgentClient _agent;
  final SessionTokenStore _tokenStore;
  final _jobUpdatesController = StreamController<DeployJob>.broadcast();
  late final RemoteLocalRunSession _localRun;

  bool _paired = false;
  bool _jobEventsLoopRunning = false;
  Future<void> Function()? _onUnauthorized;

  bool get isPaired => _paired;

  Stream<DeployJob> get jobUpdates => _jobUpdatesController.stream;

  LocalRunControls get localRun => _localRun;

  DeployTrigger deployTrigger({void Function()? onSessionEnded}) {
    Future<void> endSession() async {
      await unpair();
      onSessionEnded?.call();
    }

    _onUnauthorized = endSession;
    _localRun.setOnUnauthorized(endSession);

    return DeployTrigger(
      title: 'Deploy',
      showUnpair: true,
      preferredPlatforms: const [DeployPlatform.macos, DeployPlatform.ios],
      unreachableHint: 'Is the Mac companion running at $agentBaseUrl?',
      listProjects: listProjects,
      evaluateSourceChanges: evaluateSourceChanges,
      startDeploy: startDeploy,
      fetchJob: fetchJob,
      fetchActiveJob: fetchActiveJob,
      listDeployHistory: listDeployHistory,
      fetchDeployQueue: fetchDeployQueue,
      cancelQueuedDeploy: cancelQueuedDeploy,
      jobUpdates: jobUpdates,
      onUnauthorized: endSession,
      onUnpair: endSession,
    );
  }

  Future<void> restore() async {
    final token = await _tokenStore.loadToken();
    _agent.setBearerToken(token);
    _paired = token != null;
    if (_paired) {
      _ensureJobEventsListening();
      _localRun.startListening();
    }
  }

  Future<void> pair(String pin) async {
    final token = await _agent.pair(
      pin,
      label: Platform.isIOS ? 'iPhone' : Platform.localHostname,
    );
    await _tokenStore.saveToken(token);
    _paired = true;
    _ensureJobEventsListening();
    _localRun.startListening();
  }

  Future<void> unpair() async {
    _paired = false;
    _localRun.stopListening();
    _agent.cancelJobEvents();
    await _tokenStore.clearToken();
    _agent.setBearerToken(null);
  }

  Future<List<DeployableProject>> listProjects() => _agent.listProjects();

  Future<List<DeployableProject>> evaluateSourceChanges({
    void Function(SourceChangesProgress progress)? onProgress,
  }) {
    return _agent.evaluateSourceChanges();
  }

  Future<DeployJob> startDeploy({
    required String projectId,
    required DeployPlatform platform,
    bool force = false,
  }) {
    return _agent.startDeploy(
      projectId: projectId,
      platform: platform,
      force: force,
    );
  }

  Future<DeployJob> fetchJob(String jobId) => _agent.fetchJob(jobId);

  Future<DeployJob?> fetchActiveJob() => _agent.fetchActiveJob();

  Future<List<DeployRunRecord>> listDeployHistory() =>
      _agent.listDeployHistory();

  Future<List<DeployJob>> fetchDeployQueue() => _agent.fetchDeployQueue();

  Future<void> cancelQueuedDeploy(String jobId) =>
      _agent.cancelQueuedDeploy(jobId);

  void _ensureJobEventsListening() {
    if (_jobEventsLoopRunning) {
      _log.log('job-events loop already running paired=$_paired');
      return;
    }
    _jobEventsLoopRunning = true;
    _log.log('starting job-events loop baseUrl=$agentBaseUrl');
    unawaited(_runJobEventsLoop());
  }

  Future<void> _runJobEventsLoop() async {
    var connectAttempt = 0;
    try {
      while (_paired) {
        connectAttempt += 1;
        var eventCount = 0;
        String? lastStatus;
        String? lastChecklist;
        _log.log('SSE connect attempt=$connectAttempt');
        try {
          await for (final job in _agent.watchJobEvents()) {
            if (!_paired) break;
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
            'paired=$_paired',
          );
        } on AgentRequestException catch (error) {
          _log.warn(
            'SSE AgentRequestException attempt=$connectAttempt '
            'status=${error.statusCode} ${error.message}',
          );
          if (error.isUnauthorized) {
            final onUnauthorized = _onUnauthorized;
            if (onUnauthorized != null) {
              await onUnauthorized();
            } else {
              await unpair();
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
        if (!_paired) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } finally {
      _jobEventsLoopRunning = false;
      _log.log('job-events loop stopped paired=$_paired');
    }
  }

  void close() {
    _paired = false;
    unawaited(_localRun.close());
    _agent.cancelJobEvents();
    unawaited(_jobUpdatesController.close());
    _agent.close();
  }
}
