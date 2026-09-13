import 'dart:async';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../run/flutter_run_device.dart';
import '../run/local_run_controls.dart';
import '../run/local_run_key.dart';
import '../run/local_run_registry.dart';
import '../run/local_run_screen.dart';
import 'workbench_project.dart';

/// Start / stop a Mac-side local run and show [LocalRunDetail] (rail or screen).
class const ProjectLocalRunFlow({
  /// When set (Mac wide workbench), show the run in the side rail instead of
  /// pushing [LocalRunScreen].
  final void Function(LocalRunControls controls)? showRunInSideRailOrRunScreen,
}) {
  Future<void> startOrShowLocalRun(
    BuildContext context, {
    required LocalRunRegistry registry,
    required WorkbenchProject project,
    required FlutterRunDevice device,
  }) async {
    final controls = registry.controlsFor(
      LocalRunKey(projectId: project.projectId, deviceKey: device.key),
    );

    if (controls.state.status.isActive) {
      _showLocalRun(context, controls);
      return;
    }

    _showLocalRun(context, controls);
    try {
      await controls.start(project, device: device);
    } catch (error) {
      if (!context.mounted) return;
      context.textSnackBar(error.toString());
    }
  }

  Future<void> stop(
    BuildContext context, {
    required LocalRunRegistry registry,
    required WorkbenchProject project,
    required FlutterRunDevice device,
  }) async {
    final controls = registry.controlsFor(
      LocalRunKey(projectId: project.projectId, deviceKey: device.key),
    );
    if (!controls.isActive) return;
    try {
      await controls.stop();
    } catch (error) {
      if (!context.mounted) return;
      context.textSnackBar(error.toString());
    }
  }

  void _showLocalRun(BuildContext context, LocalRunControls controls) {
    final showInRailOrRunScreen = showRunInSideRailOrRunScreen;
    if (showInRailOrRunScreen != null) {
      showInRailOrRunScreen(controls);
      return;
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => LocalRunScreen(session: controls),
        ),
      ),
    );
  }
}
