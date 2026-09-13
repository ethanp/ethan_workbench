import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';

import '../run/os_process_tree.dart';

const _log = ELogger('ListeningTcpPort');

/// A TCP port that may already have a leftover listener (same machine).
class const ListeningTcpPort(final int port) {
  Future<List<int>> get listenerPids async {
    final result = await Process.run('lsof', [
      '-nP',
      '-iTCP:$port',
      '-sTCP:LISTEN',
      '-t',
    ]);
    return pidsFromLsof(result.stdout as String);
  }

  /// SIGTERM any other process listening here so this app can bind.
  Future<void> killOtherListenersTillExit() async {
    final occupyingPids = await listenerPids;
    for (final listenerPid in occupyingPids) {
      if (listenerPid == pid) continue;
      _log.warn('Reclaiming port $port from pid $listenerPid');
      await listenerPid.asOsProcessTree.killTillExit();
    }
  }

  static List<int> pidsFromLsof(String stdout) {
    final pids = <int>{};
    for (final line in stdout.split('\n')) {
      final listenerPid = int.tryParse(line.trim());
      if (listenerPid == null || listenerPid <= 0) continue;
      pids.add(listenerPid);
    }
    return pids.toList();
  }
}

extension AsListeningTcpPort on int {
  ListeningTcpPort get asListeningTcpPort => ListeningTcpPort(this);
}

extension SocketAddressInUse on SocketException {
  bool get isAddressInUse {
    final code = osError?.errorCode;
    if (code == 48 || code == 98) return true;
    return message.contains('Address already in use');
  }
}
