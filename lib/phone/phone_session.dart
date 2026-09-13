import '../deploy/deploy_trigger.dart';
import '../run/local_run_registry.dart';
import '../server/server_endpoint.dart';
import '../server/workbench_lan_session.dart';
import 'deploy_http_client.dart';
import 'server_password_store.dart';

/// iOS client session: restore shared password, talk to the Mac server.
class PhoneSession({
  DeployServerClient? serverClient,
  ServerPasswordStore? passwordStore,
}) {
  this {
    _lanSession = WorkbenchLanSession(
      deployServerClient: _deployServerClient,
      unreachableHint: 'Is the Mac server running at $serverBaseUrl?',
    );
  }

  final DeployServerClient _deployServerClient =
      serverClient ?? DeployServerClient();
  final ServerPasswordStore _passwordStore =
      passwordStore ?? ServerPasswordStore();
  late final WorkbenchLanSession _lanSession;

  bool _signedIn = false;

  bool get isSignedIn => _signedIn;

  LocalRunRegistry get localRunRegistry => _lanSession.localRunRegistry;

  DeployTrigger deployTrigger({void Function()? onSessionEnded}) {
    Future<void> endSession() async {
      await signOut();
      onSessionEnded?.call();
    }

    return _lanSession.deployTrigger(
      onUnauthorized: endSession,
      onSignOut: endSession,
      showSignOut: true,
    );
  }

  Future<void> restore() async {
    final password = await _passwordStore.loadPassword();
    _deployServerClient.setBearerToken(password);
    _signedIn = password != null;
    if (_signedIn) {
      _lanSession.startListening();
    }
  }

  Future<void> signIn(String password) async {
    _deployServerClient.setBearerToken(password);
    await _lanSession.listProjects();
    await _passwordStore.savePassword(password);
    _signedIn = true;
    _lanSession.startListening();
  }

  Future<void> signOut() async {
    _signedIn = false;
    _lanSession.stopListening();
    await _passwordStore.clearPassword();
    _deployServerClient.setBearerToken(null);
  }

  void close() {
    _signedIn = false;
    _lanSession.close();
  }
}
