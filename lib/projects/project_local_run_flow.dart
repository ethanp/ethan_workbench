import 'package:flutter/material.dart';

import '../run/flutter_run_device.dart';
import '../run/local_run_controls.dart';
import '../run/local_run_screen.dart';
import '../run/local_run_state.dart';
import 'deployable_project.dart';

/// Start / switch / stop a Mac-side local run and open [LocalRunScreen].
class ProjectLocalRunFlow {
  const ProjectLocalRunFlow();

  Future<void> open(
    BuildContext context, {
    required LocalRunControls session,
    required DeployableProject project,
    required FlutterRunDevice device,
  }) async {
    final activeState = session.state;

    // Stopping is still "active" — open the console to watch it finish instead
    // of snackbarring LocalRunAlreadyActive or offering a switch dialog.
    if (activeState.status == LocalRunStatus.stopping) {
      await _openConsole(context, session);
      return;
    }

    if (activeState.status.isActive &&
        activeState.projectId == project.projectId &&
        activeState.deviceKey == device.key) {
      await _openConsole(context, session);
      return;
    }

    if (activeState.status.isActive &&
        (activeState.projectId != project.projectId ||
            activeState.deviceKey != device.key)) {
      final shouldSwitch = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Stop current run?'),
          content: Text(
            '${activeState.projectName ?? 'Another app'}'
            '${activeState.deviceLabel != null ? ' (${activeState.deviceLabel})' : ''} '
            'is already running. Stop it and run ${project.name} on ${device.label}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Switch'),
            ),
          ],
        ),
      );
      if (shouldSwitch != true || !context.mounted) return;
      try {
        await session.stop();
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
        return;
      }
      if (!context.mounted) return;
    }

    try {
      await session.start(project, device: device);
    } catch (error) {
      if (!context.mounted) return;
      if (error is LocalRunAlreadyActive &&
          session.state.status == LocalRunStatus.stopping) {
        await _openConsole(context, session);
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      return;
    }
    if (!context.mounted) return;
    await _openConsole(context, session);
  }

  Future<void> stop(
    BuildContext context, {
    required LocalRunControls session,
  }) async {
    if (!session.isActive) return;
    try {
      await session.stop();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openConsole(BuildContext context, LocalRunControls session) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LocalRunScreen(session: session),
      ),
    );
  }
}
