import 'package:ethan_utils/ethan_utils.dart';
import 'package:path/path.dart' as path;

import '../app_identity.dart';
import 'server_endpoint.dart';

class ServerConfig {
  final int port;
  final List<String> flutterRoots;
  final String deployRbPath;

  ServerConfig({int? port, List<String>? flutterRoots, String? deployRbPath})
    : port = port ?? serverPort,
      flutterRoots = flutterRoots ?? [workbenchFlutterRoot],
      deployRbPath = deployRbPath ?? workbenchDeployRbPath;

  static String get defaultFlutterRoot => workbenchFlutterRoot;
  static String get defaultDeployRbPath => workbenchDeployRbPath;
  static int get defaultPort => serverPort;
}

String get workbenchFlutterRoot => envStringOr('FLUTTER_ROOT', '');

/// Prefer `DEPLOY_RB`; otherwise `<flutterRoot>/<syncAppName>/deploy.rb`.
String get workbenchDeployRbPath {
  final configured = envString('DEPLOY_RB');
  if (configured != null) return configured;
  final flutterRoot = workbenchFlutterRoot;
  if (flutterRoot.isEmpty) return '';
  return path.join(flutterRoot, AppIdentity.syncAppName, 'deploy.rb');
}
