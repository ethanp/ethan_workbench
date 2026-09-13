import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_platform.dart';
import 'flutter_run_device.dart';
import 'local_run_key.dart';
import 'local_run_state.dart';

/// Clickable list of live local runs at the top of the Run pane.
class const LocalRunSwitcher({
  required final List<LocalRunState> sessions,
  required final LocalRunKey? selectedRunKey,
  required final ValueChanged<LocalRunKey> onSessionSelected,
  final VoidCallback? onDismiss,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ELayout.spaceMd,
        0,
        ELayout.spaceMd,
        ELayout.spaceMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(),
          const SizedBox(height: ELayout.spaceSm),
          for (var index = 0; index < sessions.length; index++) ...[
            if (index > 0) const SizedBox(height: ELayout.spaceSm),
            _RunningAppTile(
              runState: sessions[index],
              selected: sessions[index].runKey == selectedRunKey,
              onSelected: onSessionSelected,
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader() {
    return Row(
      children: [
        Expanded(child: Text('Running', style: EText.label.small)),
        if (onDismiss != null)
          IconButton(
            tooltip: 'Close',
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: EColors.textMuted,
          ),
      ],
    );
  }
}

class const _RunningAppTile({
  required final LocalRunState runState,
  required final bool selected,
  required final ValueChanged<LocalRunKey> onSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final runKey = runState.runKey;
    return ESurface(
      key: runKey == null ? null : ValueKey(runKey.fileName),
      kind: ESurfaceKind.tinted,
      accent: _devicePlatform.accent,
      onActivated: selected || runKey == null
          ? null
          : () => onSelected(runKey),
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      child: Row(
        children: [
          Icon(
            _devicePlatform.icon,
            size: 12,
            color: _devicePlatform.accent,
          ),
          const SizedBox(width: ELayout.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  runState.projectAndDeviceLabel,
                  style: EText.label.medium.copyWith(
                    color: EColors.textPrimary,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  runState.status.chipLabel,
                  style: EText.caption.copyWith(
                    fontSize: ELayout.typeSize(11),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (selected)
            Icon(
              Icons.check_rounded,
              size: 16,
              color: _devicePlatform.accent,
            ),
        ],
      ),
    );
  }

  DeployPlatform get _devicePlatform {
    if (runState.deviceKey == FlutterRunDevice.macos.key) {
      return DeployPlatform.macos;
    }
    return DeployPlatform.ios;
  }
}
