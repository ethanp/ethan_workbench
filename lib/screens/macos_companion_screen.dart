import 'dart:async';

import 'package:flutter/material.dart';

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
  bool _busy = false;

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
    await _startServer();
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
      subtitle: _server.isRunning ? 'Ready for deploys' : 'Offline offline',
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

  Widget _endpointPanel() {
    return AppPanel(
      title: 'Endpoint',
      subtitle: 'Hardcoded phone target',
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
