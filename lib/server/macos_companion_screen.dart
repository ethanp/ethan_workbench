import 'dart:async';

import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_identity.dart';
import '../deploy/deploy_history_screen.dart';
import '../deploy/deploy_job.dart';
import '../projects/projects_screen.dart';
import '../sync/deploy_ledger.dart';
import '../sync/sync_config.dart';
import 'package:ethan_ui/ethan_ui.dart';

import '../ui/widgets/deploy_platform_controls.dart';
import '../ui/widgets/deploy_progress_checklist.dart';
import '../ui/widgets/status_pill.dart';
import 'deploy_server.dart';
import 'server_config.dart';
import 'server_endpoint.dart';

class MacosCompanionScreen extends StatefulWidget {
  const MacosCompanionScreen({this.syncContainer});

  final ProviderContainer? syncContainer;

  @override
  State<MacosCompanionScreen> createState() => _MacosCompanionScreenState();
}

class _MacosCompanionScreenState extends State<MacosCompanionScreen> {
  final _server = DeployServer();
  String? _lanAddress;
  String? _statusMessage;
  DeployJob? _activeJob;
  StreamSubscription<DeployJob>? _jobSubscription;
  bool _busy = false;
  int _tabIndex = 0;
  int _ledgerGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    unawaited(_jobSubscription?.cancel());
    unawaited(_server.dispose());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final lanAddress = await firstLanIpv4Address();
    setState(() => _lanAddress = lanAddress);
    await _server.restoreLocalRun();
    if (mounted) setState(() {});
    // Server must come up even if PowerSync ledger attach is slow/hangs.
    await _startServer(announce: false);
    await _attachSyncLedger();
    await _server.restoreDeploySession();
    if (mounted) {
      setState(() => _activeJob = _server.activeJob);
    }
  }

  Future<void> _attachSyncLedger() async {
    if (!ethanWorkbenchSyncConfigured()) return;
    final container = widget.syncContainer;
    if (container == null) return;
    final databaseManager = await container.read(
      powerSyncDatabaseManagerProvider.future,
    );
    _server.attachLedger(DeployLedger(databaseManager.database));
    if (mounted) setState(() => _ledgerGeneration++);
  }

  void _showServerMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    context.textSnackBar(message);
  }

  Future<void> _startServer({bool announce = true}) async {
    if (_busy || _server.isRunning) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      await _server.start();
      await _jobSubscription?.cancel();
      _jobSubscription = _server.jobUpdates.listen((job) {
        if (!mounted) return;
        setState(() => _activeJob = job);
      });
      if (!mounted) return;
      setState(() {
        _activeJob = _server.activeJob;
        _statusMessage = null;
      });
      if (announce) {
        _showServerMessage(
          'Server listening on port '
          '${_server.boundPort ?? ServerConfig.defaultPort}',
        );
      }
    } catch (error) {
      final message = 'Failed to start: $error';
      if (mounted) setState(() => _statusMessage = message);
      _showServerMessage(message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopServer() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _jobSubscription?.cancel();
      _jobSubscription = null;
      await _server.stop();
      if (!mounted) return;
      setState(() => _statusMessage = 'Server stopped');
      _showServerMessage('Server stopped');
    } catch (error) {
      final message = 'Failed to stop: $error';
      if (mounted) setState(() => _statusMessage = message);
      _showServerMessage(message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EColors.background,
      body: IndexedStack(
        index: _tabIndex,
        children: [
          ProjectsScreen(
            trigger: _server.localDeployTrigger,
            localRun: _server.localRun,
          ),
          DeployHistoryScreen(
            key: ValueKey(_ledgerGeneration),
            trigger: _server.localDeployTrigger,
          ),
          _serverTab(),
        ],
      ),
      bottomNavigationBar: EFrostedBottomBar(
        child: ESegmentedControl(
          selectedIndex: _tabIndex,
          onSelected: (index) => setState(() => _tabIndex = index),
          segments: const [
            ESegment(
              icon: Icons.rocket_launch_rounded,
              label: 'Deploy',
            ),
            ESegment(
              icon: Icons.history_rounded,
              label: 'History',
            ),
            ESegment(
              icon: Icons.dns_rounded,
              label: 'Server',
            ),
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
        subtitle: 'iOS client endpoint',
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
            Text(_statusMessage!, style: EText.caption),
          ],
        ],
      ),
    );
  }

  Widget _serverPanel() {
    return EPanel(
      title: 'Server',
      subtitle: _server.isRunning ? 'Ready for the iOS client' : 'Server offline',
      trailing: StatusPill.server(running: _server.isRunning),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Port ${_server.boundPort ?? ServerConfig.defaultPort}',
            style: EText.mono,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (_server.isRunning)
                const OutlinedButton(
                  onPressed: null,
                  child: Text('Start'),
                )
              else
                FilledButton(
                  onPressed: _busy ? null : () => unawaited(_startServer()),
                  child: Text(_busy ? 'Starting…' : 'Start'),
                ),
              const SizedBox(width: 10),
              if (_server.isRunning)
                FilledButton(
                  onPressed: _busy ? null : () => unawaited(_stopServer()),
                  child: const Text('Stop'),
                )
              else
                const OutlinedButton(
                  onPressed: null,
                  child: Text('Stop'),
                ),
            ],
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Text(_statusMessage!, style: EText.caption),
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
            child: SelectableText(
              serverBaseUrl,
              style: EText.monoEmphasis,
            ),
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
            style: EText.body.copyWith(
              color: passwordConfigured ? null : EColors.warning,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Keep this window open while deploying from the phone.',
            style: EText.body,
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
              'Deploys from this Mac or the iOS client show live logs here.',
              style: EText.body,
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
