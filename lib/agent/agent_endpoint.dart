import 'package:ethan_utils/ethan_utils.dart';

/// LAN agent address from `.env` (see `.env.example`).
String get phoneDeployAgentHost =>
    envStringOr('PHONE_DEPLOY_AGENT_HOST', 'localhost');

int get phoneDeployAgentPort => envIntOr('PHONE_DEPLOY_AGENT_PORT', 8787);

String get phoneDeployAgentBaseUrl =>
    'http://$phoneDeployAgentHost:$phoneDeployAgentPort';
