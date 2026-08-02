import 'package:ethan_utils/ethan_utils.dart';
import 'package:path/path.dart' as path;

import 'agent_endpoint.dart';

class AgentConfig {
  final int port;
  final List<String> flutterRoots;
  final String deployRbPath;

  AgentConfig({int? port, List<String>? flutterRoots, String? deployRbPath})
    : port = port ?? phoneDeployAgentPort,
      flutterRoots = flutterRoots ?? [phoneDeployFlutterRoot],
      deployRbPath = deployRbPath ?? phoneDeployDeployRbPath;

  static String get defaultFlutterRoot => phoneDeployFlutterRoot;
  static String get defaultDeployRbPath => phoneDeployDeployRbPath;
  static int get defaultPort => phoneDeployAgentPort;
}

String get phoneDeployFlutterRoot =>
    envStringOr('PHONE_DEPLOY_FLUTTER_ROOT', '');

/// Prefer `PHONE_DEPLOY_DEPLOY_RB`; otherwise `<flutterRoot>/phone_deploy/deploy.rb`.
String get phoneDeployDeployRbPath {
  final configured = envString('PHONE_DEPLOY_DEPLOY_RB');
  if (configured != null) return configured;
  final flutterRoot = phoneDeployFlutterRoot;
  if (flutterRoot.isEmpty) return '';
  return path.join(flutterRoot, 'phone_deploy', 'deploy.rb');
}
