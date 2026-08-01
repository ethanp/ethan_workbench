import 'dart:async';

import 'package:ethan_sync/ethan_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../deploy/deploy_job.dart';
import '../projects/projects_screen.dart';
import '../sync/deploy_ledger.dart';
import '../sync/sync_config.dart';
import '../ui/theme/app_colors.dart';
import '../ui/theme/app_text.dart';
import '../ui/widgets/app_panel.dart';
import '../ui/widgets/deploy_platform_controls.dart';
import '../ui/widgets/deploy_progress_checklist.dart';
import '../ui/widgets/log_console.dart';
import '../ui/widgets/status_pill.dart';
import 'agent_config.dart';
import 'agent_endpoint.dart';
import 'deploy_agent.dart';

class MacosCompanionScreen extends StatefulWidget {
  const MacosCompanionScreen({super.key, this.syncContainer});

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
    await _attachSyncLedger();
    await _startAgent();
  }

  Future<void> _attachSyncLedger() async {
    if (!phoneDeploySyncConfigured()) return;
    final container = widget.syncContainer;
    if (container == null) return;
    final databaseManager =
        await container.read(powerSyncDatabaseManagerProvider.future);
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
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _tabIndex,
        children: [
          ProjectsScreen(trigger: _agent.localDeployTrigger),
          _agentTab(),
        ],
      ),
      bottomNavigationBar: Material(
        color: AppColors.surface,
        elevation: 0,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
            child: Center(
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceInset,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _companionTab(
                        index: 0,
                        icon: Icons.rocket_launch_rounded,
                        label: 'Deploy',
                      ),
                      _companionTab(
                        index: 1,
                        icon: Icons.dns_rounded,
                        label: 'Agent',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _companionTab({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = _tabIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _tabIndex = index),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppColors.accentGlow : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppText.section.copyWith(
                  fontSize: 14,
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _agentTab() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Phone Deploy'),
            Text('Mac companion', style: AppText.caption),
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
            Text(_statusMessage!, style: AppText.caption),
          ],
        ],
      ),
    );
  }

  Widget _serverPanel() {
    return AppPanel(
      title: 'Agent',
      subtitle: _agent.isRunning ? 'Ready for deploys' : 'Agent offline',
      trailing: StatusPill.server(running: _agent.isRunning),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Port ${_agent.boundPort ?? AgentConfig.defaultPort}',
            style: AppText.mono,
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
    return AppPanel(
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
              style: AppText.body,
            )
          else ...[
            Text('PIN', style: AppText.label),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _formattedPin,
                    style: AppText.mono.copyWith(
                      fontSize: 36,
                      letterSpacing: 4,
                      color: AppColors.accentGlow,
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied PIN')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Enter this on the phone. Refreshes in ${secondsLeft}s.',
              style: AppText.caption,
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: pairingAuth.rotatePin,
              child: const Text('New PIN'),
            ),
            const SizedBox(height: 18),
            Text('CONNECTED', style: AppText.label),
            const SizedBox(height: 8),
            if (sessions.isEmpty)
              Text(
                'No phones paired yet.',
                style: AppText.body,
              )
            else ...[
              for (final session in sessions) ...[
                _sessionRow(session.sessionId, session.label, session.pairedAt),
                const SizedBox(height: 8),
              ],
              OutlinedButton(
                onPressed: () {
                  pairingAuth.revokeAllSessions();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Revoked all phone sessions'),
                    ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceInset,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.section),
                  Text('Paired $time', style: AppText.caption),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                _agent.pairingAuth.revokeSession(sessionId);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Revoked $label')),
                );
              },
              child: Text(
                'Revoke',
                style: AppText.body.copyWith(color: AppColors.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _endpointPanel() {
    return AppPanel(
      title: 'Endpoint',
      subtitle: 'Phone target from .env',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceInset,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: SelectableText(
                phoneDeployAgentBaseUrl,
                style: AppText.monoEmphasis,
              ),
            ),
          ),
          if (_lanAddress != null) ...[
            const SizedBox(height: 10),
            Text(
              'LAN IP $_lanAddress · fallback if .local fails',
              style: AppText.caption,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Keep this window open while deploying from the phone.',
            style: AppText.body,
          ),
        ],
      ),
    );
  }

  Widget _jobPanel() {
    final job = _activeJob;
    return AppPanel(
      title: 'Active job',
      subtitle: job == null ? 'Waiting for a deploy' : job.projectName,
      trailing: job == null ? null : StatusPill.job(job.status),
      child: job == null
          ? Text(
              'Deploys from this Mac or a paired iPhone show live logs here.',
              style: AppText.body,
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
                      style: AppText.caption,
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
