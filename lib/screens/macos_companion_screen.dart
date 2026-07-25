import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../agent/agent_config.dart';
import '../agent/agent_endpoint.dart';
import '../agent/deploy_agent_server.dart';
import '../api/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_panel.dart';
import '../widgets/log_console.dart';
import '../widgets/status_pill.dart';

class MacosCompanionScreen extends StatefulWidget {
  const MacosCompanionScreen({super.key});

  @override
  State<MacosCompanionScreen> createState() => _MacosCompanionScreenState();
}

class _MacosCompanionScreenState extends State<MacosCompanionScreen> {
  final _server = DeployAgentServer();
  String? _lanAddress;
  String? _statusMessage;
  DeployJob? _activeJob;
  StreamSubscription<DeployJob>? _jobSubscription;
  StreamSubscription<void>? _pairingSubscription;
  Timer? _pinTicker;
  bool _busy = false;

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
    unawaited(_server.dispose());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final lanAddress = await firstLanIpv4Address();
    setState(() => _lanAddress = lanAddress);
    await _startServer();
  }

  void _listenPairingUpdates() {
    unawaited(_pairingSubscription?.cancel());
    _pairingSubscription = _server.pairingAuth.updates.listen((_) {
      if (mounted) setState(() {});
    });
    _pinTicker?.cancel();
    _pinTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _server.pairingAuth.ensureFreshPin();
      setState(() {});
    });
  }

  Future<void> _startServer() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      await _server.start();
      await _jobSubscription?.cancel();
      _jobSubscription = _server.jobRunner.jobUpdates.listen((job) {
        if (!mounted) return;
        setState(() => _activeJob = job);
      });
      _listenPairingUpdates();
      setState(() {
        _activeJob = _server.jobRunner.activeJob;
        _statusMessage = null;
      });
    } catch (error) {
      setState(() => _statusMessage = 'Failed to start: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopServer() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _pinTicker?.cancel();
      _pinTicker = null;
      await _pairingSubscription?.cancel();
      _pairingSubscription = null;
      await _jobSubscription?.cancel();
      _jobSubscription = null;
      await _server.stop();
      setState(() => _statusMessage = 'Server stopped');
    } catch (error) {
      setState(() => _statusMessage = 'Failed to stop: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _formattedPin {
    final pin = _server.pairingAuth.pin;
    return '${pin.substring(0, 3)} ${pin.substring(3)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      subtitle: _server.isRunning ? 'Ready for deploys' : 'Agent offline',
      trailing: StatusPill.server(running: _server.isRunning),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Port ${_server.boundPort ?? AgentConfig.defaultPort}',
            style: AppText.mono,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton(
                onPressed: _busy || _server.isRunning ? null : _startServer,
                child: const Text('Start'),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _busy || !_server.isRunning ? null : _stopServer,
                child: const Text('Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pairingPanel() {
    final pairingAuth = _server.pairingAuth;
    final secondsLeft = pairingAuth.pinTimeRemaining.inSeconds;
    final sessions = pairingAuth.sessions;
    return AppPanel(
      title: 'Pairing',
      subtitle: _server.isRunning
          ? '${sessions.length} connected device'
              '${sessions.length == 1 ? '' : 's'}'
          : 'Start the agent to show a PIN',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_server.isRunning)
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
                  pairingAuth.clearSessions();
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
                _server.pairingAuth.revokeSession(sessionId);
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
      subtitle: job?.projectName ?? 'Waiting for the phone',
      trailing: job == null ? null : StatusPill.job(job.status),
      child: job == null
          ? Text(
              'Deployments triggered from the iPhone appear here with live logs.',
              style: AppText.body,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (job.force)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text('Force rebuild', style: AppText.caption),
                  ),
                LogConsole(log: job.log, maxHeight: 260),
              ],
            ),
    );
  }
}
