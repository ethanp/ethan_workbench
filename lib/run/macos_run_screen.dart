import 'dart:async';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import 'macos_run_session.dart';
import 'macos_run_state.dart';

class MacosRunScreen extends StatefulWidget {
  const MacosRunScreen({required this.session});

  final MacosRunSession session;

  @override
  State<MacosRunScreen> createState() => _MacosRunScreenState();
}

class _MacosRunScreenState extends State<MacosRunScreen> {
  late MacosRunState _state;
  StreamSubscription<MacosRunState>? _subscription;
  final _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _state = widget.session.state;
    _subscription = widget.session.updates.listen((state) {
      if (!mounted) return;
      final shouldStickToBottom =
          !_logScrollController.hasClients ||
          _logScrollController.position.pixels >=
              _logScrollController.position.maxScrollExtent - 40;
      setState(() => _state = state);
      if (shouldStickToBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_logScrollController.hasClients) return;
          _logScrollController.jumpTo(
            _logScrollController.position.maxScrollExtent,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_state.projectName ?? 'macOS run'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusPanel(),
            const SizedBox(height: 14),
            _actions(),
            const SizedBox(height: 14),
            Text('RUN LOG', style: EText.label),
            const SizedBox(height: 8),
            Expanded(
              child: LogConsole(
                log: _state.log,
                controller: _logScrollController,
                emptyMessage: '(waiting for flutter run…)',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPanel() {
    return ESurface(
      kind: ESurfaceKind.panel,
      padding: const EdgeInsets.all(ELayout.spaceMd + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EStatusChip(
                label: _statusLabel,
                tone: _statusTone,
                uppercase: true,
              ),
              if (_state.readyForKeyCommands) ...[
                const SizedBox(width: 10),
                const EStatusChip(
                  label: 'ready',
                  tone: EStatusTone.success,
                  uppercase: true,
                ),
              ],
              if (_state.reattached) ...[
                const SizedBox(width: 10),
                const EStatusChip(
                  label: 'reattached',
                  tone: EStatusTone.warning,
                  uppercase: true,
                ),
              ],
              if (_state.exitCode != null) ...[
                const SizedBox(width: 10),
                Text('Exit ${_state.exitCode}', style: EText.caption),
              ],
            ],
          ),
          if (_state.reattached) ...[
            const SizedBox(height: 8),
            Text(
              _state.readyForKeyCommands
                  ? 'Workbench restarted while this app was running — '
                      'reattached; hot reload is available.'
                  : 'Workbench restarted while this app was running. '
                      'Attaching… if hot reload stays disabled, use Full restart.',
              style: EText.caption,
            ),
          ],
          if (_state.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _state.errorMessage!,
              style: EText.body.copyWith(color: EColors.danger),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions() {
    final canKeys = _state.readyForKeyCommands;
    final canStop = _state.status.isActive;
    final canFullRestart = _state.projectPath != null &&
        _state.status != MacosRunStatus.starting &&
        _state.status != MacosRunStatus.stopping;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.tonal(
          onPressed: canKeys
              ? () => unawaited(widget.session.hotReload())
              : null,
          child: const Text('Hot reload'),
        ),
        FilledButton.tonal(
          onPressed: canKeys
              ? () => unawaited(widget.session.hotRestart())
              : null,
          child: const Text('Hot restart'),
        ),
        FilledButton.tonal(
          onPressed: canFullRestart
              ? () => unawaited(widget.session.fullRestart())
              : null,
          child: const Text('Full restart'),
        ),
        OutlinedButton(
          onPressed: canStop ? () => unawaited(widget.session.stop()) : null,
          child: const Text('Stop'),
        ),
      ],
    );
  }

  String get _statusLabel => switch (_state.status) {
    MacosRunStatus.idle => 'idle',
    MacosRunStatus.starting => 'starting',
    MacosRunStatus.running => 'running',
    MacosRunStatus.stopping => 'stopping',
    MacosRunStatus.exited => 'exited',
    MacosRunStatus.failed => 'failed',
  };

  EStatusTone get _statusTone => switch (_state.status) {
    MacosRunStatus.idle => EStatusTone.muted,
    MacosRunStatus.starting => EStatusTone.accent,
    MacosRunStatus.running => EStatusTone.success,
    MacosRunStatus.stopping => EStatusTone.warning,
    MacosRunStatus.exited => EStatusTone.muted,
    MacosRunStatus.failed => EStatusTone.danger,
  };
}
