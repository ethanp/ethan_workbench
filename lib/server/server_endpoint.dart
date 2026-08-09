import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';

/// LAN deploy server address + shared password from `.env` (see `.env.example`).
String get serverHost => envStringOr('SERVER_HOST', 'localhost');

int get serverPort => envIntOr('SERVER_PORT', 8787);

/// Shared password the iOS client sends as `Authorization: Bearer …`.
/// Empty/unset → middleware fails closed (no open LAN access).
String get serverPassword => envStringOr('SERVER_PASSWORD', '');

String get serverBaseUrl => 'http://$serverHost:$serverPort';

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
