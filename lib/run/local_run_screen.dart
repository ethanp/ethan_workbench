import 'dart:async';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'flutter_run_exception.dart';
import 'local_flutter_run.dart';
import 'local_run_controls.dart';
import 'local_run_state.dart';

class LocalRunScreen extends StatefulWidget {
  const LocalRunScreen({required this.session});

  final LocalRunControls session;

  @override
  State<LocalRunScreen> createState() => _LocalRunScreenState();
}

class _LocalRunScreenState extends State<LocalRunScreen> {
  late LocalRunState _state;
  StreamSubscription<LocalRunState>? _subscription;

  @override
  void initState() {
    super.initState();
    _state = widget.session.state;
    _subscription = widget.session.updates.listen((state) {
      if (!mounted) return;
      setState(() => _state = state);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _state.deviceLabel == null
        ? (_state.projectName ?? 'Local run')
        : '${_state.projectName ?? 'App'} · ${_state.deviceLabel}';
    return EScaffoldShell(
      appBar: AppBar(title: Text(title, style: EText.title)),
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
                emptyMessage: '(waiting for flutter run…)',
                trimBeforeLastHighlight: true,
                highlights: [
                  LogConsoleHighlight(
                    pattern: FlutterRunOutput.sessionResetPattern,
                    color: EColors.success,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPanel() {
    final flutterException = _state.flutterException;
    return ESurface(
      kind: ESurfaceKind.panel,
      padding: const EdgeInsets.all(ELayout.spaceMd + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EStatusChip(
                label: _state.status.chipLabel,
                tone: _state.status.chipTone,
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
              if (flutterException != null) ...[
                const SizedBox(width: 10),
                const EStatusChip(
                  label: 'exception',
                  tone: EStatusTone.danger,
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
          if (flutterException != null) ...[
            const SizedBox(height: 10),
            _exceptionHighlight(flutterException),
          ],
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

  Widget _exceptionHighlight(FlutterRunException flutterException) {
    final widgetName = flutterException.widget;
    final location = flutterException.displayLocation;
    final creatorChain = flutterException.creatorChain;
    final constraints = flutterException.constraints;
    final size = flutterException.size;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GestureDetector(
                onLongPress: () => unawaited(_copyExceptionPrompt()),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widgetName != null)
                      Text(
                        widgetName,
                        style: EText.section.copyWith(color: EColors.danger),
                      ),
                    if (location != null)
                      Text(
                        location,
                        style: EText.mono.copyWith(
                          color: EColors.danger,
                          fontSize: ELayout.typeSize(12),
                        ),
                      ),
                    if (flutterException.library != null)
                      Text(
                        flutterException.library!,
                        style: EText.caption.copyWith(
                          color: EColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copy for Cursor',
              onPressed: () => unawaited(_copyExceptionPrompt()),
              icon: const Icon(Icons.copy_rounded),
              color: EColors.danger,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (creatorChain != null) ...[
          const SizedBox(height: 6),
          Text(
            creatorChain,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: EText.caption.copyWith(color: EColors.textSecondary),
          ),
        ],
        if (constraints != null || size != null) ...[
          const SizedBox(height: 4),
          Text(
            [
              ?constraints,
              if (size != null) 'size: $size',
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: EText.caption.copyWith(color: EColors.textMuted),
          ),
        ],
      ],
    );
  }

  Future<void> _copyExceptionPrompt() async {
    final flutterException = _state.flutterException;
    if (flutterException == null) return;
    await Clipboard.setData(ClipboardData(text: flutterException.promptText));
    if (!mounted) return;
    context.textSnackBar('Copied for Cursor');
  }

  Widget _actions() {
    final canKeys = _state.readyForKeyCommands;
    final canStop = _state.status.isActive;
    final canFullRestart =
        _state.projectPath != null &&
        _state.status != LocalRunStatus.starting &&
        _state.status != LocalRunStatus.stopping;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _runAction(
                accent: EColors.success,
                icon: Icons.bolt_rounded,
                title: 'Hot reload',
                enabled: canKeys,
                onActivated: () => unawaited(widget.session.hotReload()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _runAction(
                accent: EColors.warning,
                icon: Icons.restart_alt_rounded,
                title: 'Hot restart',
                enabled: canKeys,
                onActivated: () => unawaited(widget.session.hotRestart()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _runAction(
                accent: EColors.accentGlow,
                icon: Icons.replay_circle_filled_rounded,
                title: 'Full restart',
                enabled: canFullRestart,
                onActivated: () => unawaited(widget.session.fullRestart()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _runAction(
                accent: EColors.danger,
                icon: Icons.stop_circle_rounded,
                title: 'Stop',
                enabled: canStop,
                onActivated: () => unawaited(widget.session.stop()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _runAction({
    required Color accent,
    required IconData icon,
    required String title,
    required bool enabled,
    required VoidCallback onActivated,
  }) {
    final plate = ETintedAction.compact(
      accent: enabled ? accent : EColors.textMuted,
      icon: icon,
      title: title,
      onActivated: enabled ? onActivated : () {},
    );
    if (enabled) return plate;
    return Opacity(opacity: 0.42, child: IgnorePointer(child: plate));
  }
}
