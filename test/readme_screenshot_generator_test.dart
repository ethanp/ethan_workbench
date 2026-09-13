import 'dart:async';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_workbench/deploy/deploy_job.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/deploy/deploy_run_record.dart';
import 'package:ethan_workbench/deploy/deploy_trigger.dart';
import 'package:ethan_workbench/projects/projects_screen.dart';
import 'package:ethan_workbench/projects/source_changes_progress.dart';
import 'package:ethan_workbench/projects/workbench_project.dart';
import 'package:ethan_workbench/run/flutter_run_device.dart';
import 'package:ethan_workbench/run/local_run_controls.dart';
import 'package:ethan_workbench/run/local_run_key.dart';
import 'package:ethan_workbench/run/local_run_registry.dart';
import 'package:ethan_workbench/run/local_run_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _desktopSize = Size(1600, 900);

void main() {
  setUpAll(ETheme.loadFontsForWidgetTests);

  testWidgets('writes projects homescreen for README', (tester) async {
    await tester.binding.setSurfaceSize(_desktopSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final bookTrack = _runningControls(
      projectId: 'book_track',
      projectName: 'book_track',
      device: FlutterRunDevice.macos,
    );
    final registry = _StubLocalRunRegistry([
      bookTrack,
      _idleControls(
        projectId: 'workouts',
        projectName: 'workouts',
        device: FlutterRunDevice.macos,
      ),
      _idleControls(
        projectId: 'spend_trends',
        projectName: 'spend_trends',
        device: FlutterRunDevice.macos,
      ),
      _idleControls(
        projectId: 'health_notes',
        projectName: 'health_notes',
        device: FlutterRunDevice.macos,
      ),
    ]);
    addTearDown(registry.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ETheme.material3Dark,
        debugShowCheckedModeBanner: false,
        home: ProjectsScreen(
          trigger: _trigger(
            [
              _macosProject('book_track'),
              _macosProject('workouts'),
              _macosProject('spend_trends'),
              _macosProject('health_notes'),
            ],
            activeJob: DeployJob(
              jobId: 'job-workouts',
              projectId: 'workouts',
              projectName: 'workouts',
              platform: DeployPlatform.ios,
              force: false,
              status: DeployJobStatus.running,
              log: 'building…',
              createdAt: DateTime(2026, 9, 12),
            ),
          ),
          localRunRegistry: registry,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../screenshots/projects.png'),
    );
  });
}

WorkbenchProject _macosProject(String name) => WorkbenchProject(
  projectId: name,
  name: name,
  path: '/tmp/$name',
  platforms: {DeployPlatform.macos, DeployPlatform.ios},
);

DeployTrigger _trigger(
  List<WorkbenchProject> projects, {
  DeployJob? activeJob,
}) {
  return DeployTrigger(
    listProjects: () async => projects,
    evaluateSourceChanges:
        ({void Function(SourceChangesProgress progress)? onProgress}) async {
          return projects;
        },
    startDeploy: ({
      required String projectId,
      required DeployPlatform platform,
      bool force = false,
    }) async => throw UnimplementedError(),
    fetchJob: (jobId) async {
      if (activeJob?.jobId == jobId) return activeJob!;
      throw UnimplementedError();
    },
    fetchActiveJob: () async => activeJob,
    listDeployHistory: () async => const <DeployRunRecord>[],
    fetchDeployQueue: () async => const <DeployJob>[],
    cancelQueuedDeploy: (jobId) async {},
    reorderQueuedDeploy: ({required jobId, required toIndex}) async {},
  );
}

_StubLocalRunControls _runningControls({
  required String projectId,
  required String projectName,
  required FlutterRunDevice device,
}) {
  return _StubLocalRunControls(
    LocalRunState(
      status: LocalRunStatus.running,
      log: 'A Dart VM Service on ${device.label} is available',
      readyForKeyCommands: true,
      projectId: projectId,
      projectName: projectName,
      projectPath: '/tmp/$projectId',
      deviceKey: device.key,
      deviceLabel: device.label,
      flutterDeviceId: device.flutterDeviceId,
    ),
  );
}

_StubLocalRunControls _idleControls({
  required String projectId,
  required String projectName,
  required FlutterRunDevice device,
}) {
  return _StubLocalRunControls(
    LocalRunState(
      status: LocalRunStatus.idle,
      log: '',
      readyForKeyCommands: false,
      projectId: projectId,
      projectName: projectName,
      projectPath: '/tmp/$projectId',
      deviceKey: device.key,
      deviceLabel: device.label,
      flutterDeviceId: device.flutterDeviceId,
    ),
  );
}

class _StubLocalRunRegistry implements LocalRunRegistry {
  _StubLocalRunRegistry(List<_StubLocalRunControls> slots) {
    for (final slot in slots) {
      final runKey = slot.state.runKey;
      if (runKey == null) {
        throw StateError('stub run is missing projectId/deviceKey');
      }
      _slots[runKey] = slot;
    }
  }

  final Map<LocalRunKey, _StubLocalRunControls> _slots = {};
  final _changes = StreamController<void>.broadcast();
  final _stateUpdates = StreamController<LocalRunState>.broadcast();

  void dispose() {
    unawaited(_changes.close());
    unawaited(_stateUpdates.close());
    for (final slot in _slots.values) {
      slot.dispose();
    }
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Stream<LocalRunState> get stateUpdates => _stateUpdates.stream;

  @override
  List<LocalRunState> get knownStates => [
    for (final slot in _slots.values) slot.state,
  ];

  @override
  int get activeCount =>
      _slots.values.where((slot) => slot.isActive).length;

  @override
  LocalRunState stateFor(LocalRunKey runKey) =>
      _slots[runKey]?.state ?? LocalRunState.idle;

  @override
  LocalRunControls controlsFor(LocalRunKey runKey) {
    return _slots.putIfAbsent(
      runKey,
      () => _StubLocalRunControls(LocalRunState.idle),
    );
  }
}

class _StubLocalRunControls implements LocalRunControls {
  _StubLocalRunControls(this._state);

  LocalRunState _state;
  final _updates = StreamController<LocalRunState>.broadcast();

  void dispose() {
    unawaited(_updates.close());
  }

  @override
  LocalRunState get state => _state;

  @override
  Stream<LocalRunState> get updates => _updates.stream;

  @override
  bool get isActive => _state.status.isActive;

  @override
  Future<void> start(
    WorkbenchProject project, {
    required FlutterRunDevice device,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> hotReload() async {}

  @override
  Future<void> hotRestart() async {}

  @override
  Future<void> fullRestart() async {}
}
