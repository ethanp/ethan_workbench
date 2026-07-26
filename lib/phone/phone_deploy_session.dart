import 'dart:io';

import '../deploy/deploy_job.dart';
import '../pairing/session_token_store.dart';
import '../projects/deployable_project.dart';
import 'deploy_http_client.dart';

/// Phone-side session: restore pairing, talk to the Mac agent, unpair on revoke.
class PhoneDeploySession {
  PhoneDeploySession({
    MacAgentClient? agentClient,
    SessionTokenStore? tokenStore,
  })  : _agent = agentClient ?? MacAgentClient(),
        _tokenStore = tokenStore ?? SessionTokenStore();

  final MacAgentClient _agent;
  final SessionTokenStore _tokenStore;
  bool _paired = false;

  bool get isPaired => _paired;

  Future<void> restore() async {
    final token = await _tokenStore.loadToken();
    _agent.setBearerToken(token);
    _paired = token != null;
  }

  Future<void> pair(String pin) async {
    final token = await _agent.pair(
      pin,
      label: Platform.isIOS ? 'iPhone' : Platform.localHostname,
    );
    await _tokenStore.saveToken(token);
    _paired = true;
  }

  Future<void> unpair() async {
    await _tokenStore.clearToken();
    _agent.setBearerToken(null);
    _paired = false;
  }

  Future<List<DeployableProject>> listProjects() => _agent.listProjects();

  Future<DeployJob> startDeploy({
    required String projectId,
    bool force = false,
  }) {
    return _agent.startDeploy(projectId: projectId, force: force);
  }

  Future<DeployJob> fetchJob(String jobId) => _agent.fetchJob(jobId);

  void close() => _agent.close();
}
