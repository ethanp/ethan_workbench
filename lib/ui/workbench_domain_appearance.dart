import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_job.dart';
import '../deploy/deploy_platform.dart';
import '../projects/workbench_project.dart';
import '../run/local_run_state.dart';

extension DeployPlatformAppearance on DeployPlatform {
  IconData get icon => switch (this) {
    DeployPlatform.ios => Icons.phone_iphone_rounded,
    DeployPlatform.macos => Icons.desktop_mac_rounded,
  };

  Color get accent => switch (this) {
    DeployPlatform.ios => EColors.platformIos,
    DeployPlatform.macos => EColors.platformMacos,
  };

  Color get accentSoft => switch (this) {
    DeployPlatform.ios => EColors.platformIosSoft,
    DeployPlatform.macos => EColors.platformMacosSoft,
  };

  EStatusTone get badgeTone => switch (this) {
    DeployPlatform.ios => EStatusTone.accent,
    DeployPlatform.macos => EStatusTone.muted,
  };
}

extension DeployJobStatusAppearance on DeployJobStatus {
  EStatusTone get statusTone => switch (this) {
    DeployJobStatus.waiting => EStatusTone.pending,
    DeployJobStatus.queued => EStatusTone.pending,
    DeployJobStatus.running => EStatusTone.accent,
    DeployJobStatus.succeeded => EStatusTone.success,
    DeployJobStatus.failed => EStatusTone.danger,
  };
}

extension LocalRunStatusAppearance on LocalRunStatus {
  EStatusTone get chipTone => switch (this) {
    LocalRunStatus.idle => EStatusTone.muted,
    LocalRunStatus.starting => EStatusTone.accent,
    LocalRunStatus.running => EStatusTone.success,
    LocalRunStatus.stopping => EStatusTone.warning,
    LocalRunStatus.exited => EStatusTone.muted,
    LocalRunStatus.failed => EStatusTone.danger,
  };
}

extension DeploySourceStatusAppearance on DeploySourceStatus {
  EStatusTone? get chipTone => switch (this) {
    DeploySourceStatus.unevaluated => null,
    DeploySourceStatus.neverDeployed => null,
    DeploySourceStatus.unchanged => EStatusTone.success,
    DeploySourceStatus.changed => EStatusTone.warning,
  };
}
