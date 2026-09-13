import 'dart:io';

import 'package:ethan_workbench/server/listening_tcp_port.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pidsFromLsof reads one pid per line and skips junk', () {
    expect(
      ListeningTcpPort.pidsFromLsof('55799\n55801\n\nnot-a-pid\n0\n'),
      [55799, 55801],
    );
  });

  test('SocketException reports address-in-use from macOS errno 48', () {
    final exception = SocketException(
      'Failed to create server socket (OS Error: Address already in use, errno = 48)',
      osError: const OSError('Address already in use', 48),
      address: InternetAddress.anyIPv4,
      port: 8787,
    );
    expect(exception.isAddressInUse, isTrue);
  });

  test('SocketException is not address-in-use for other failures', () {
    final exception = SocketException(
      'Connection refused',
      osError: const OSError('Connection refused', 61),
    );
    expect(exception.isAddressInUse, isFalse);
  });
}
