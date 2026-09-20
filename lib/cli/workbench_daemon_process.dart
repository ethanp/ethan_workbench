import 'dart:async';
import 'dart:io';

import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../server/deploy_server.dart';
import '../server/listening_tcp_port.dart';
import '../server/server_endpoint.dart';
import '../server/workbench_loopback.dart';
import '../sync/deploy_ledger.dart';
import '../sync/sync_config.dart';

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

    final stopped = Completer<void>();
    ProviderContainer? syncContainer;
    late final DeployServer deployServer;
    Future<void> requestStop() async {
      if (stopped.isCompleted) return;
      stdout.writeln('Stopping workbench daemon…');
      await deployServer.dispose();
      syncContainer?.dispose();
      stopped.complete();
    }

    deployServer = DeployServer(onExitRequested: () => unawaited(requestStop()));
    try {
      await deployServer.restoreLocalRun();
      await deployServer.start(takeOverOccupiedPort: false);
      syncContainer = await _attachDeployLedger(deployServer);
      await deployServer.restoreDeploySession();
    } on SocketException catch (error) {
      if (error.isAddressInUse) {
        stdout.writeln(
          'Port $serverPort is already in use. '
          'If that is the workbench daemon, it is already running.',
        );
        await deployServer.dispose();
        syncContainer?.dispose();
        return;
      }
      rethrow;
    }

    _log.log('Listening on $loopbackServerBaseUrl');
    stdout.writeln('Workbench daemon listening on $loopbackServerBaseUrl');

    ProcessSignal.sigint.watch().listen((_) => unawaited(requestStop()));
    ProcessSignal.sigterm.watch().listen((_) => unawaited(requestStop()));
    await stopped.future;
  }

  /// History and last-deployed times live in PowerSync. The Mac UI is only an
  /// HTTP client when the daemon owns :8787, so the daemon must attach the
  /// ledger or `/jobs/history` stays empty.
  static Future<ProviderContainer?> _attachDeployLedger(
    DeployServer deployServer,
  ) async {
    if (!ethanWorkbenchSyncConfigured()) {
      stdout.writeln(
        'Deploy history ledger skipped (PowerSync not configured in .env)',
      );
      return null;
    }
    try {
      final syncContainer = ProviderContainer(
        overrides: [
          syncConfigProvider.overrideWith(
            (ref) => buildEthanWorkbenchSyncConfig(),
          ),
        ],
      );
      final manager = await syncContainer.read(
        powerSyncDatabaseManagerProvider.future,
      );
      deployServer.attachLedger(DeployLedger(manager.database));
      stdout.writeln('Deploy history ledger attached');
      try {
        await SyncLifecycle.start(
          syncContainer,
          schedulePostFrameReprobe: false,
        );
      } catch (error, stackTrace) {
        _log.warn(
          'PowerSync connect failed; History still reads the local ledger',
          error,
          stackTrace,
        );
      }
      return syncContainer;
    } catch (error, stackTrace) {
      _log.warn('Deploy history ledger not attached', error, stackTrace);
      stdout.writeln('Deploy history ledger not attached: $error');
      return null;
    }
  }
}
