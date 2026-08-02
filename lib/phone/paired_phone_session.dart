import 'dart:async';
import 'dart:io';

import '../agent/agent_endpoint.dart';
import '../app_identity.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_run_record.dart';
import '../deploy/deploy_trigger.dart';
import '../pairing/session_token_store.dart';
import '../projects/deployable_project.dart';
import '../run/local_run_controls.dart';
import '../run/remote_local_run_session.dart';
import 'deploy_http_client.dart';

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
      title: AppIdentity.displayName,
      showUnpair: true,
      preferredPlatforms: const [DeployPlatform.macos, DeployPlatform.ios],
      unreachableHint: 'Is the Mac companion running at $agentBaseUrl?',
      listProjects: listProjects,
      evaluateSourceChanges: evaluateSourceChanges,
      startDeploy: startDeploy,
      fetchJob: fetchJob,
      fetchActiveJob: fetchActiveJob,
      listDeployHistory: listDeployHistory,
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

  Future<List<DeployableProject>> evaluateSourceChanges() =>
      _agent.evaluateSourceChanges();

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

  void _ensureJobEventsListening() {
    if (_jobEventsLoopRunning) return;
    _jobEventsLoopRunning = true;
    unawaited(_runJobEventsLoop());
  }

  Future<void> _runJobEventsLoop() async {
    try {
      while (_paired) {
        try {
          await for (final job in _agent.watchJobEvents()) {
            if (!_paired) break;
            if (!_jobUpdatesController.isClosed) {
              _jobUpdatesController.add(job);
            }
          }
        } on AgentRequestException catch (error) {
          if (error.isUnauthorized) {
            final onUnauthorized = _onUnauthorized;
            if (onUnauthorized != null) {
              await onUnauthorized();
            } else {
              await unpair();
            }
            break;
          }
        } catch (_) {
          // Reconnect below while still paired.
        }
        if (!_paired) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } finally {
      _jobEventsLoopRunning = false;
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
