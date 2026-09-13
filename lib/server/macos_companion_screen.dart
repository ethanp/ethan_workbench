import 'dart:async';

import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_identity.dart';
import '../deploy/deploy_history_screen.dart';
import '../deploy/deploy_job.dart';
import '../deploy/deploy_trigger.dart';
import '../phone/deploy_http_client.dart';
import '../projects/projects_screen.dart';
import '../run/local_run_registry.dart';
import '../sync/deploy_ledger.dart';
import '../sync/sync_config.dart';

import 'package:ethan_ui/ethan_ui.dart';

import '../ui/widgets/deploy_platform_controls.dart';
import '../ui/widgets/deploy_progress_checklist.dart';
import '../ui/widgets/status_pill.dart';
import 'deploy_server.dart';
import 'server_config.dart';
import 'server_endpoint.dart';
import 'workbench_lan_session.dart';
import 'workbench_loopback.dart';

const _log = ELogger('MacosCompanion');

class const MacosCompanionScreen({final ProviderContainer? syncContainer})
    extends StatefulWidget {
  @override
  State<MacosCompanionScreen> createState() => _MacosCompanionScreenState();
}

class _MacosCompanionScreenState() extends State<MacosCompanionScreen> {
  DeployServer? _inProcessServer;
  WorkbenchLanSession? _daemonSession;
  String? _lanAddress;
  String? _statusMessage;
  DeployJob? _activeJob;
  StreamSubscription<DeployJob>? _jobSubscription;
  bool _busy = false;
  int _tabIndex = 0;
  int _ledgerGeneration = 0;

  bool get _usingDaemon => _daemonSession != null;

  bool get _isListening =>
      _usingDaemon || (_inProcessServer?.isRunning ?? false);

  DeployTrigger get _deployTrigger {
    final daemonSession = _daemonSession;
    if (daemonSession != null) {
      return daemonSession.deployTrigger(
        showLineAgeAnalysis: true,
        flutterRoots: ServerConfig().flutterRoots,
      );
    }
    return _inProcessServer!.localDeployTrigger;
  }

  LocalRunRegistry get _localRunRegistry {
    return _daemonSession?.localRunRegistry ??
        _inProcessServer!.localRunRegistry;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_connectToDaemonOrStartInProcess());
  }

  @override
  void dispose() {
    unawaited(_jobSubscription?.cancel());
    _daemonSession?.close();
    unawaited(_inProcessServer?.dispose());
    super.dispose();
  }

  Future<void> _connectToDaemonOrStartInProcess() async {
    final lanAddress = await firstLanIpv4Address();
    if (mounted) setState(() => _lanAddress = lanAddress);

    if (await WorkbenchLoopback.isHealthy) {
      _attachDaemonSession();
      return;
    }

    final inProcessServer = DeployServer();
    _inProcessServer = inProcessServer;
    await inProcessServer.restoreLocalRun();
    if (mounted) setState(() {});
    await _startInProcessServer(announce: false);
    await _attachSyncLedger();
    await inProcessServer.restoreDeploySession();
    if (mounted) {
      setState(() => _activeJob = inProcessServer.activeJob);
    }
  }

  void _attachDaemonSession() {
    final daemonSession = WorkbenchLanSession(
      deployServerClient: DeployServerClient(baseUrl: loopbackServerBaseUrl)
        ..setBearerToken(serverPassword),
      unreachableHint:
          'Is the workbench daemon running at $loopbackServerBaseUrl?',
    );
    _daemonSession = daemonSession;
    daemonSession.startListening();
    unawaited(_jobSubscription?.cancel());
    _jobSubscription = daemonSession.jobUpdates.listen((job) {
      if (!mounted) return;
      setState(() => _activeJob = job);
    });
    unawaited(_refreshActiveJobFromDaemon());
    if (mounted) {
      setState(() {
        _statusMessage = 'Using workbench daemon on $loopbackServerBaseUrl';
      });
    }
  }

  Future<void> _refreshActiveJobFromDaemon() async {
    try {
      final job = await _daemonSession?.fetchActiveJob();
      if (!mounted) return;
      setState(() => _activeJob = job);
    } catch (error, stackTrace) {
      _log.warn('Failed to load active job from daemon', error, stackTrace);
    }
  }

  Future<void> _attachSyncLedger() async {
    if (!ethanWorkbenchSyncConfigured()) return;
    final inProcessServer = _inProcessServer;
    if (inProcessServer == null) return;
    final container = widget.syncContainer;
    if (container == null) return;
    final databaseManager = await container.read(
      powerSyncDatabaseManagerProvider.future,
    );
    inProcessServer.attachLedger(DeployLedger(databaseManager.database));
    if (mounted) setState(() => _ledgerGeneration++);
  }

  void _showServerMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    context.textSnackBar(message);
  }

  Future<void> _startInProcessServer({bool announce = true}) async {
    final inProcessServer = _inProcessServer;
    if (_busy || inProcessServer == null || inProcessServer.isRunning) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      await inProcessServer.start(takeOverOccupiedPort: true);
      await _jobSubscription?.cancel();
      _jobSubscription = inProcessServer.jobUpdates.listen((job) {
        if (!mounted) return;
        setState(() => _activeJob = job);
      });
      if (!mounted) return;
      setState(() {
        _activeJob = inProcessServer.activeJob;
        _statusMessage = null;
      });
      if (announce) {
        _showServerMessage(
          'Server listening on port '
          '${inProcessServer.boundPort ?? ServerConfig.defaultPort}',
        );
      }
    } catch (error, stackTrace) {
      final message = 'Failed to start: $error';
      _log.error(message, error, stackTrace);
      if (mounted) setState(() => _statusMessage = message);
      _showServerMessage(message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopInProcessServer() async {
    final inProcessServer = _inProcessServer;
    if (_busy || inProcessServer == null) return;
    setState(() => _busy = true);
    try {
      await _jobSubscription?.cancel();
      _jobSubscription = null;
      await inProcessServer.stop();
      if (!mounted) return;
      setState(() => _statusMessage = 'Server stopped');
      _showServerMessage('Server stopped');
    } catch (error, stackTrace) {
      final message = 'Failed to stop: $error';
      _log.error(message, error, stackTrace);
      if (mounted) setState(() => _statusMessage = message);
      _showServerMessage(message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_daemonSession == null && _inProcessServer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: EColors.background,
      body: IndexedStack(
        index: _tabIndex,
        children: [
          ProjectsScreen(
            trigger: _deployTrigger,
            localRunRegistry: _localRunRegistry,
          ),
          DeployHistoryScreen(
            key: ValueKey(_ledgerGeneration),
            trigger: _deployTrigger,
          ),
          _serverTab(),
        ],
      ),
      bottomNavigationBar: EFrostedBottomBar(
        child: ESegmentedControl(
          selectedIndex: _tabIndex,
          onSelected: (index) => setState(() => _tabIndex = index),
          segments: const [
            ESegment(icon: Icons.rocket_launch_rounded, label: 'Deploy'),
            ESegment(icon: Icons.history_rounded, label: 'History'),
            ESegment(icon: Icons.dns_rounded, label: 'Server'),
          ],
        ),
      ),
    );
  }

  Widget _serverTab() {
    return EScaffoldShell(
      appBar: EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: 'Server',
        subtitle: _usingDaemon
            ? 'Workbench daemon on loopback'
            : 'iOS client endpoint',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _serverPanel(),
          const SizedBox(height: 14),
          _endpointPanel(),
          const SizedBox(height: 14),
          _jobPanel(),
          if (_statusMessage != null) ...[
            const SizedBox(height: 16),
            SelectableText(_statusMessage!, style: EText.caption),
          ],
          const SizedBox(height: 14),
          const SizedBox(
            height: 280,
            child: EAppLogViewer(maxBodyHeight: 220),
          ),
        ],
      ),
    );
  }

  Widget _serverPanel() {
    return EPanel(
      title: 'Server',
      subtitle: _usingDaemon
          ? 'Using workbench daemon'
          : (_inProcessServer?.isRunning ?? false)
          ? 'Ready for the iOS client'
          : 'Server offline',
      trailing: StatusPill.server(running: _isListening),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _usingDaemon
                ? loopbackServerBaseUrl
                : 'Port ${_inProcessServer?.boundPort ?? ServerConfig.defaultPort}',
            style: EText.mono,
          ),
          const SizedBox(height: 14),
          if (_usingDaemon)
            Text(
              'Stop or start the daemon with scripts/workbench daemon.',
              style: EText.body.medium,
            )
          else
            Row(
              children: [
                if (_inProcessServer?.isRunning ?? false)
                  const OutlinedButton(onPressed: null, child: Text('Start'))
                else
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => unawaited(_startInProcessServer()),
                    child: Text(_busy ? 'Starting…' : 'Start'),
                  ),
                const SizedBox(width: 10),
                if (_inProcessServer?.isRunning ?? false)
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => unawaited(_stopInProcessServer()),
                    child: const Text('Stop'),
                  )
                else
                  const OutlinedButton(onPressed: null, child: Text('Stop')),
              ],
            ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            SelectableText(_statusMessage!, style: EText.caption),
          ],
        ],
      ),
    );
  }

  Widget _endpointPanel() {
    final passwordConfigured = serverPassword.isNotEmpty;
    return EPanel(
      title: 'Endpoint',
      subtitle: 'iOS client target from .env',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ESurface(
            kind: ESurfaceKind.inset,
            borderRadius: ELayout.borderRadiusSm,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: SelectableText(serverBaseUrl, style: EText.monoEmphasis),
          ),
          if (_lanAddress != null) ...[
            const SizedBox(height: 10),
            Text(
              'LAN IP $_lanAddress · fallback if .local fails',
              style: EText.caption,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            passwordConfigured
                ? 'Auth: SERVER_PASSWORD from .env (shared with the iOS client).'
                : 'SERVER_PASSWORD is empty — set it in .env or the iOS client '
                      'cannot sign in.',
            style: EText.body.medium.copyWith(
              color: passwordConfigured ? null : EColors.warning,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _usingDaemon
                ? 'The workbench daemon owns the HTTP port. This window is a client.'
                : 'Keep this window open while deploying from the phone, '
                      'or run scripts/workbench daemon start.',
            style: EText.body.medium,
          ),
        ],
      ),
    );
  }

  Widget _jobPanel() {
    final job = _activeJob;
    return EPanel(
      title: 'Active job',
      subtitle: job == null ? 'Waiting for a deploy' : job.projectName,
      trailing: job == null ? null : StatusPill.job(job.status),
      child: job == null
          ? Text(
              'Deploys from this Mac, the CLI, or the iOS client show here.',
              style: EText.body.medium,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DeployPlatformBadge(platform: job.platform),
                    const SizedBox(width: 10),
                    Text(
                      job.force ? 'Force rebuild' : 'Incremental deploy',
                      style: EText.caption,
                    ),
                  ],
                ),
                if (job.checklist.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DeployProgressChecklist(items: job.checklist),
                ],
                const SizedBox(height: 12),
                LogConsole(log: job.log, maxHeight: 260),
              ],
            ),
    );
  }
}
