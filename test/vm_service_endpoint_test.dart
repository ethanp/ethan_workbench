import 'dart:io';

import 'package:ethan_workbench/run/vm_service_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing URI is not listening', () async {
    expect(await const VmServiceEndpoint(null).isListening, isFalse);
    expect(await const VmServiceEndpoint('').isListening, isFalse);
  });

  test('open port is listening', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((socket) {
      socket.destroy();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close();
    });

    final endpoint = VmServiceEndpoint(
      'http://127.0.0.1:${server.port}/token=/',
    );
    expect(await endpoint.isListening, isTrue);
  });

  test('closed port is not listening', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();

    final endpoint = VmServiceEndpoint('http://127.0.0.1:$port/token=/');
    expect(await endpoint.isListening, isFalse);
  });
}
