import 'dart:async';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'flutter_run_exception.dart';
import 'local_flutter_run.dart';
import 'local_run_controls.dart';
import 'local_run_state.dart';

/// Live local-run status, commands, and log. Full-screen or Mac side rail.
class const LocalRunDetail({
  super.key,
  required final LocalRunControls session,

  /// Side-rail run detail (no scaffold).
  final bool inSideRail = false,

  /// Shown in the side-rail header; omitted in full-screen (AppBar back).
  final VoidCallback? onDismiss,
}) extends StatefulWidget {
  @override
  State<LocalRunDetail> createState() => _LocalRunDetailState();
}

class _LocalRunDetailState() extends State<LocalRunDetail> {
  static const _twoAcrossActionsMinWidth = 240.0;
  static const _actionGap = 10.0;

  late LocalRunState _state;
  StreamSubscription<LocalRunState>? _subscription;

  @override
  void initState() {
    super.initState();
    _listenToSession();
  }

  @override
  void didUpdateWidget(covariant LocalRunDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.session, widget.session)) return;
    unawaited(_subscription?.cancel());
    _listenToSession();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _listenToSession() {
    _state = widget.session.state;
    _subscription = widget.session.updates.listen((state) {
      if (!mounted) return;
      setState(() => _state = state);
    });
  }

  String get _title {
    if (_state.deviceLabel == null) {
      return _state.projectName ?? 'Local run';
    }
    return '${_state.projectName ?? 'App'} · ${_state.deviceLabel}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inSideRail) return _sideRailBody();
    return EScaffoldShell(
      appBar: AppBar(
        title: Text(
          _title,
          style: EText.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: _runColumn(),
      ),
    );
  }

  Widget _sideRailBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sideRailHeader(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ELayout.spaceMd,
              0,
              ELayout.spaceMd,
              ELayout.spaceMd,
            ),
            child: _runColumn(),
          ),
        ),
      ],
    );
  }

  Widget _sideRailHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ELayout.spaceMd,
        ELayout.spaceSm,
        ELayout.spaceXs,
        ELayout.spaceSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _title,
              style: EText.label.medium.copyWith(color: EColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.onDismiss != null)
            IconButton(
              tooltip: 'Close',
              onPressed: widget.onDismiss,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
              color: EColors.textMuted,
            ),
        ],
      ),
    );
  }

  Widget _runColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statusPanel(),
        const SizedBox(height: 14),
        _actions(),
        const SizedBox(height: 14),
        Text('RUN LOG', style: EText.label.small),
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
          _statusChips(),
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
              style: EText.body.medium.copyWith(color: EColors.danger),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChips() {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        EStatusChip(
          label: _state.status.chipLabel,
          tone: _state.status.chipTone,
          uppercase: true,
        ),
        if (_state.readyForKeyCommands)
          const EStatusChip(
            label: 'ready',
            tone: EStatusTone.success,
            uppercase: true,
          ),
        if (_state.flutterException != null)
          const EStatusChip(
            label: 'exception',
            tone: EStatusTone.danger,
            uppercase: true,
          ),
        if (_state.reattached)
          const EStatusChip(
            label: 'reattached',
            tone: EStatusTone.warning,
            uppercase: true,
          ),
        if (_state.exitCode != null)
          Text('Exit ${_state.exitCode}', style: EText.caption),
      ],
    );
  }

  Widget _exceptionHighlight(FlutterRunException flutterException) {
    final creatorChain = flutterException.creatorChain;
    final constraints = flutterException.constraints;
    final size = flutterException.size;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _exceptionHeader(flutterException),
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
            [?constraints, if (size != null) 'size: $size'].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: EText.caption.copyWith(color: EColors.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _exceptionHeader(FlutterRunException flutterException) {
    final details = GestureDetector(
      onLongPress: () => unawaited(_copyExceptionPrompt()),
      child: _exceptionDetails(flutterException),
    );
    final copyButton = IconButton(
      tooltip: 'Copy for Cursor',
      onPressed: () => unawaited(_copyExceptionPrompt()),
      icon: const Icon(Icons.copy_rounded),
      color: EColors.danger,
      visualDensity: VisualDensity.compact,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 72) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [details, copyButton],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Expanded(child: details), copyButton],
        );
      },
    );
  }

  Widget _exceptionDetails(FlutterRunException flutterException) {
    final widgetName = flutterException.widget;
    final location = flutterException.displayLocation;
    return Column(
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
            style: EText.caption.copyWith(color: EColors.textMuted),
          ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final double tileWidth =
            constraints.maxWidth >= _twoAcrossActionsMinWidth
            ? (constraints.maxWidth - _actionGap) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: _actionGap,
          runSpacing: _actionGap,
          children: [
            for (final plate in _runCommandPlates())
              SizedBox(width: tileWidth, child: plate),
          ],
        );
      },
    );
  }

  List<Widget> _runCommandPlates() {
    final canKeys = _state.readyForKeyCommands;
    final canStop = _state.status.isActive;
    final canFullRestart =
        _state.projectPath != null &&
        _state.status != LocalRunStatus.starting &&
        _state.status != LocalRunStatus.stopping;
    return [
      _runAction(
        accent: EColors.success,
        icon: Icons.bolt_rounded,
        title: 'Hot reload',
        enabled: canKeys,
        onActivated: () => unawaited(widget.session.hotReload()),
      ),
      _runAction(
        accent: EColors.warning,
        icon: Icons.restart_alt_rounded,
        title: 'Hot restart',
        enabled: canKeys,
        onActivated: () => unawaited(widget.session.hotRestart()),
      ),
      _runAction(
        accent: EColors.accentGlow,
        icon: Icons.replay_circle_filled_rounded,
        title: 'Full restart',
        enabled: canFullRestart,
        onActivated: () => unawaited(widget.session.fullRestart()),
      ),
      _runAction(
        accent: EColors.danger,
        icon: Icons.stop_circle_rounded,
        title: 'Stop',
        enabled: canStop,
        onActivated: () => unawaited(widget.session.stop()),
      ),
    ];
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

/// Full-screen run route (phone / compact).
class const LocalRunScreen({required final LocalRunControls session})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => LocalRunDetail(session: session);
}
