import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../run/flutter_run_device.dart';
import '../run/local_run_controls.dart';
import '../run/local_run_key.dart';
import '../run/local_run_registry.dart';
import '../run/local_run_screen.dart';
import 'deployable_project.dart';

/// Start / stop a Mac-side local run and open [LocalRunScreen].
class ProjectLocalRunFlow {
  const ProjectLocalRunFlow();

  Future<void> open(
    BuildContext context, {
    required LocalRunRegistry registry,
    required DeployableProject project,
    required FlutterRunDevice device,
  }) async {
    final controls = registry.controlsFor(
      LocalRunKey(projectId: project.projectId, deviceKey: device.key),
    );
    final slotState = controls.state;

    if (slotState.status.isActive) {
      await _openConsole(context, controls);
      return;
    }

    try {
      await controls.start(project, device: device);
    } catch (error) {
      if (!context.mounted) return;
      context.textSnackBar(error.toString());
      return;
    }
    if (!context.mounted) return;
    await _openConsole(context, controls);
  }

  Future<void> stop(
    BuildContext context, {
    required LocalRunRegistry registry,
    required DeployableProject project,
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

  Future<void> _openConsole(BuildContext context, LocalRunControls controls) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LocalRunScreen(session: controls),
      ),
    );
  }
}
