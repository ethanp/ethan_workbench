import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';

import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../deploy/deploy_run_record.dart';
import '../deploy/deploy_trigger.dart';
import '../projects/deployable_project.dart';
import '../projects/source_changes_progress.dart';
import '../run/local_run_controls.dart';
import '../run/remote_local_run_session.dart';
import '../server/server_endpoint.dart';
import 'deploy_http_client.dart';
import 'server_password_store.dart';

const _log = ELogger('PhoneJobEvents');

/// iOS client session: restore shared password, talk to the Mac server.
class PhoneSession {
  PhoneSession({
    DeployServerClient? serverClient,
    ServerPasswordStore? passwordStore,
  }) : _server = serverClient ?? DeployServerClient(),
       _passwordStore = passwordStore ?? ServerPasswordStore() {
    _localRun = RemoteLocalRunSession(server: _server);
  }

  final DeployServerClient _server;
  final ServerPasswordStore _passwordStore;
  final _jobUpdatesController = StreamController<DeployJob>.broadcast();
  late final RemoteLocalRunSession _localRun;

  bool _signedIn = false;
  bool _jobEventsLoopRunning = false;
  Future<void> Function()? _onUnauthorized;

  bool get isSignedIn => _signedIn;

  Stream<DeployJob> get jobUpdates => _jobUpdatesController.stream;

  LocalRunControls get localRun => _localRun;

  DeployTrigger deployTrigger({void Function()? onSessionEnded}) {
    Future<void> endSession() async {
      await signOut();
      onSessionEnded?.call();
    }

    _onUnauthorized = endSession;
    _localRun.setOnUnauthorized(endSession);

    return DeployTrigger(
      title: 'Deploy',
      showSignOut: true,
      preferredPlatforms: const [DeployPlatform.macos, DeployPlatform.ios],
      unreachableHint: 'Is the Mac server running at $serverBaseUrl?',
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
      onSignOut: endSession,
    );
  }

  Future<void> restore() async {
    final password = await _passwordStore.loadPassword();
    _server.setBearerToken(password);
    _signedIn = password != null;
    if (_signedIn) {
      _ensureJobEventsListening();
      _localRun.startListening();
    }
  }

  Future<void> signIn(String password) async {
    _server.setBearerToken(password);
    // Verify against a protected route before persisting.
    await _server.listProjects();
    await _passwordStore.savePassword(password);
    _signedIn = true;
    _ensureJobEventsListening();
    _localRun.startListening();
  }

  Future<void> signOut() async {
    _signedIn = false;
    _localRun.stopListening();
    _server.cancelJobEvents();
    await _passwordStore.clearPassword();
    _server.setBearerToken(null);
  }

  Future<List<DeployableProject>> listProjects() => _server.listProjects();

  Future<List<DeployableProject>> evaluateSourceChanges({
    void Function(SourceChangesProgress progress)? onProgress,
  }) {
    return _server.evaluateSourceChanges();
  }

  Future<DeployJob> startDeploy({
    required String projectId,
    required DeployPlatform platform,
    bool force = false,
  }) {
    return _server.startDeploy(
      projectId: projectId,
      platform: platform,
      force: force,
    );
  }

  Future<DeployJob> fetchJob(String jobId) => _server.fetchJob(jobId);

  Future<DeployJob?> fetchActiveJob() => _server.fetchActiveJob();

  Future<List<DeployRunRecord>> listDeployHistory() =>
      _server.listDeployHistory();

  Future<List<DeployJob>> fetchDeployQueue() => _server.fetchDeployQueue();

  Future<void> cancelQueuedDeploy(String jobId) =>
      _server.cancelQueuedDeploy(jobId);

  void _ensureJobEventsListening() {
    if (_jobEventsLoopRunning) {
      _log.log('job-events loop already running signedIn=$_signedIn');
      return;
    }
    _jobEventsLoopRunning = true;
    _log.log('starting job-events loop baseUrl=$serverBaseUrl');
    unawaited(_runJobEventsLoop());
  }

  Future<void> _runJobEventsLoop() async {
    var connectAttempt = 0;
    try {
      while (_signedIn) {
        connectAttempt += 1;
        var eventCount = 0;
        String? lastStatus;
        String? lastChecklist;
        _log.log('SSE connect attempt=$connectAttempt');
        try {
          await for (final job in _server.watchJobEvents()) {
            if (!_signedIn) break;
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
            'signedIn=$_signedIn',
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
            } else {
              await signOut();
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
        if (!_signedIn) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } finally {
      _jobEventsLoopRunning = false;
      _log.log('job-events loop stopped signedIn=$_signedIn');
    }
  }

  void close() {
    _signedIn = false;
    unawaited(_localRun.close());
    _server.cancelJobEvents();
    unawaited(_jobUpdatesController.close());
    _server.close();
  }
}
