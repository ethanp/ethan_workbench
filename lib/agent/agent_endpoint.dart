import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';

/// LAN agent address from `.env` (see `.env.example`).
String get phoneDeployAgentHost =>
    envStringOr('PHONE_DEPLOY_AGENT_HOST', 'localhost');

int get phoneDeployAgentPort => envIntOr('PHONE_DEPLOY_AGENT_PORT', 8787);

String get phoneDeployAgentBaseUrl =>
    'http://$phoneDeployAgentHost:$phoneDeployAgentPort';

Future<String?> firstLanIpv4Address() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLinkLocal: false,
  );
  for (final networkInterface in interfaces) {
    for (final address in networkInterface.addresses) {
      if (address.isLoopback) continue;
      return address.address;
    }
  }
  return null;
}
