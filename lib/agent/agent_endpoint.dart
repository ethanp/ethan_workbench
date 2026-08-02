import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';

/// LAN agent address from `.env` (see `.env.example`).
String get agentHost => envStringOr('AGENT_HOST', 'localhost');

int get agentPort => envIntOr('AGENT_PORT', 8787);

String get agentBaseUrl => 'http://$agentHost:$agentPort';

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
