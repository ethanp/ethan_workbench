import 'dart:async';
import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';

import '../server/deploy_server.dart';
import '../server/listening_tcp_port.dart';
import '../server/server_endpoint.dart';
import '../server/workbench_loopback.dart';

const _log = ELogger('WorkbenchDaemon');

/// Headless [DeployServer] — one listener on [serverPort].
class WorkbenchDaemonProcess() {
  static Future<void> runUntilSignal() async {
    if (await WorkbenchLoopback.isHealthy) {
      stdout.writeln(
        'Workbench daemon already running on $loopbackServerBaseUrl',
      );
      return;
    }

    final deployServer = DeployServer();
    try {
      await deployServer.restoreLocalRun();
      await deployServer.start(takeOverOccupiedPort: false);
      await deployServer.restoreDeploySession();
    } on SocketException catch (error) {
      if (error.isAddressInUse) {
        stdout.writeln(
          'Port $serverPort is already in use. '
          'If that is the workbench daemon, it is already running.',
        );
        await deployServer.dispose();
        return;
      }
      rethrow;
    }

    _log.log('Listening on $loopbackServerBaseUrl');
    stdout.writeln('Workbench daemon listening on $loopbackServerBaseUrl');

    final stopped = Completer<void>();
    Future<void> requestStop() async {
      if (stopped.isCompleted) return;
      stdout.writeln('Stopping workbench daemon…');
      await deployServer.dispose();
      stopped.complete();
    }

    ProcessSignal.sigint.watch().listen((_) => unawaited(requestStop()));
    ProcessSignal.sigterm.watch().listen((_) => unawaited(requestStop()));
    await stopped.future;
  }
}
