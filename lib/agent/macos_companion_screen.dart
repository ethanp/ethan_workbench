import 'dart:async';

import 'package:ethan_sync/ethan_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_identity.dart';
import '../deploy/deploy_job.dart';
import '../projects/projects_screen.dart';
import '../sync/deploy_ledger.dart';
import '../sync/sync_config.dart';
import 'package:ethan_ui/ethan_ui.dart';

import '../ui/widgets/deploy_platform_controls.dart';
import '../ui/widgets/deploy_progress_checklist.dart';
import '../ui/widgets/status_pill.dart';
import 'agent_config.dart';
import 'agent_endpoint.dart';
import 'deploy_agent.dart';

class MacosCompanionScreen extends StatefulWidget {
  const MacosCompanionScreen({this.syncContainer});

  final ProviderContainer? syncContainer;

  @override
  State<MacosCompanionScreen> createState() => _MacosCompanionScreenState();
}

class _MacosCompanionScreenState extends State<MacosCompanionScreen> {
  final _agent = DeployAgent();
  String? _lanAddress;
  String? _statusMessage;
  DeployJob? _activeJob;
  StreamSubscription<DeployJob>? _jobSubscription;
  StreamSubscription<void>? _pairingSubscription;
  Timer? _pinTicker;
  bool _busy = false;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _pinTicker?.cancel();
    unawaited(_jobSubscription?.cancel());
    unawaited(_pairingSubscription?.cancel());
    unawaited(_agent.dispose());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final lanAddress = await firstLanIpv4Address();
    setState(() => _lanAddress = lanAddress);
    await _agent.restoreMacosRun();
    if (mounted) setState(() {});
    await _attachSyncLedger();
    await _startAgent();
  }

  Future<void> _attachSyncLedger() async {
    if (!ethanWorkbenchSyncConfigured()) return;
    final container = widget.syncContainer;
    if (container == null) return;
    final databaseManager = await container.read(
      powerSyncDatabaseManagerProvider.future,
    );
    _agent.attachLedger(DeployLedger(databaseManager.database));
  }

  void _listenPairingUpdates() {
    unawaited(_pairingSubscription?.cancel());
    _pairingSubscription = _agent.pairingAuth.updates.listen((_) {
      if (mounted) setState(() {});
    });
    _pinTicker?.cancel();
    _pinTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _agent.pairingAuth.ensureFreshPin();
      setState(() {});
    });
  }

  Future<void> _startAgent() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      await _agent.start();
      await _jobSubscription?.cancel();
      _jobSubscription = _agent.jobUpdates.listen((job) {
        if (!mounted) return;
        setState(() => _activeJob = job);
      });
      _listenPairingUpdates();
      setState(() {
        _activeJob = _agent.activeJob;
        _statusMessage = null;
      });
    } catch (error) {
      setState(() => _statusMessage = 'Failed to start: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopAgent() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _pinTicker?.cancel();
      _pinTicker = null;
      await _pairingSubscription?.cancel();
      _pairingSubscription = null;
      await _jobSubscription?.cancel();
      _jobSubscription = null;
      await _agent.stop();
      setState(() => _statusMessage = 'Server stopped');
    } catch (error) {
      setState(() => _statusMessage = 'Failed to stop: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _formattedPin {
    final pin = _agent.pairingAuth.pin;
    return '${pin.substring(0, 3)} ${pin.substring(3)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EColors.background,
      body: IndexedStack(
        index: _tabIndex,
        children: [
          ProjectsScreen(
            trigger: _agent.localDeployTrigger,
            macosRun: _agent.macosRun,
          ),
          _agentTab(),
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
              icon: Icons.dns_rounded,
              label: 'Agent',
            ),
          ],
        ),
      ),
    );
  }

  Widget _agentTab() {
    return EScaffoldShell(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(AppIdentity.displayName),
            Text('Mac companion', style: EText.caption),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _serverPanel(),
          const SizedBox(height: 14),
          _pairingPanel(),
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
      title: 'Agent',
      subtitle: _agent.isRunning ? 'Ready for deploys' : 'Agent offline',
      trailing: StatusPill.server(running: _agent.isRunning),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Port ${_agent.boundPort ?? AgentConfig.defaultPort}',
            style: EText.mono,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton(
                onPressed: _busy || _agent.isRunning ? null : _startAgent,
                child: const Text('Start'),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _busy || !_agent.isRunning ? null : _stopAgent,
                child: const Text('Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pairingPanel() {
    final pairingAuth = _agent.pairingAuth;
    final secondsLeft = pairingAuth.pinTimeRemaining.inSeconds;
    final sessions = pairingAuth.sessions;
    return EPanel(
      title: 'Pairing',
      subtitle: _agent.isRunning
          ? '${sessions.length} connected device'
                '${sessions.length == 1 ? '' : 's'}'
          : 'Start the agent to show a PIN',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_agent.isRunning)
            Text(
              'PIN appears when the agent is listening.',
              style: EText.body,
            )
          else ...[
            Text('PIN', style: EText.label),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _formattedPin,
                    style: EText.mono.copyWith(
                      fontSize: 36,
                      letterSpacing: 4,
                      color: EColors.accentGlow,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy PIN',
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: pairingAuth.pin),
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Copied PIN')));
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Enter this on the phone. Refreshes in ${secondsLeft}s.',
              style: EText.caption,
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: pairingAuth.rotatePin,
              child: const Text('New PIN'),
            ),
            const SizedBox(height: 18),
            Text('CONNECTED', style: EText.label),
            const SizedBox(height: 8),
            if (sessions.isEmpty)
              Text('No phones paired yet.', style: EText.body)
            else ...[
              for (final session in sessions) ...[
                _sessionRow(session.sessionId, session.label, session.pairedAt),
                const SizedBox(height: 8),
              ],
              OutlinedButton(
                onPressed: () {
                  pairingAuth.revokeAllSessions();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Revoked all phone sessions')),
                  );
                },
                child: const Text('Revoke all'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _sessionRow(String sessionId, String label, DateTime pairedAt) {
    final time = TimeOfDay.fromDateTime(pairedAt).format(context);
    return ESurface(
      kind: ESurfaceKind.inset,
      borderRadius: ELayout.borderRadiusSm,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: EText.section),
                Text('Paired $time', style: EText.caption),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              _agent.pairingAuth.revokeSession(sessionId);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Revoked $label')));
            },
            child: Text(
              'Revoke',
              style: EText.body.copyWith(color: EColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _endpointPanel() {
    return EPanel(
      title: 'Endpoint',
      subtitle: 'Phone target from .env',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ESurface(
            kind: ESurfaceKind.inset,
            borderRadius: ELayout.borderRadiusSm,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: SelectableText(
              agentBaseUrl,
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
              'Deploys from this Mac or a paired iPhone show live logs here.',
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
