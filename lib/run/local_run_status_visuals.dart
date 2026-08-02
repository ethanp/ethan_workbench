import 'package:ethan_ui/ethan_ui.dart';

import 'local_run_state.dart';

extension LocalRunStatusVisuals on LocalRunStatus {
  String get chipLabel => switch (this) {
    LocalRunStatus.starting => 'starting',
    LocalRunStatus.running => 'running',
    LocalRunStatus.stopping => 'stopping',
    LocalRunStatus.idle ||
    LocalRunStatus.exited ||
    LocalRunStatus.failed => 'idle',
  };

  EStatusTone get chipTone => switch (this) {
    LocalRunStatus.starting => EStatusTone.accent,
    LocalRunStatus.running => EStatusTone.success,
    LocalRunStatus.stopping => EStatusTone.warning,
    LocalRunStatus.idle ||
    LocalRunStatus.exited ||
    LocalRunStatus.failed => EStatusTone.muted,
  };

  String subtitleGivenIdle(String idleSubtitle) => switch (this) {
    LocalRunStatus.starting => 'Starting…',
    LocalRunStatus.running => 'Open',
    LocalRunStatus.stopping => 'Stopping…',
    LocalRunStatus.idle ||
    LocalRunStatus.exited ||
    LocalRunStatus.failed => idleSubtitle,
  };
}
