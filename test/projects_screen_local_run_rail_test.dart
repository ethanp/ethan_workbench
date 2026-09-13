import 'dart:async';

import 'package:ethan_workbench/deploy/deploy_job.dart';
import 'package:ethan_workbench/deploy/deploy_platform.dart';
import 'package:ethan_workbench/deploy/deploy_queue_panel.dart';
import 'package:ethan_workbench/deploy/deploy_run_record.dart';
import 'package:ethan_workbench/deploy/deploy_trigger.dart';
import 'package:ethan_workbench/projects/projects_screen.dart';
import 'package:ethan_workbench/projects/source_changes_progress.dart';
import 'package:ethan_workbench/projects/workbench_project.dart';
import 'package:ethan_workbench/run/flutter_run_device.dart';
import 'package:ethan_workbench/run/local_run_controls.dart';
import 'package:ethan_workbench/run/local_run_key.dart';
import 'package:ethan_workbench/run/local_run_registry.dart';
import 'package:ethan_workbench/run/local_run_screen.dart';
import 'package:ethan_workbench/run/local_run_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wide homescreen shows a restored run in the right pane', (
    tester,
  ) async {
    final registry = _StubLocalRunRegistry([
      _runningControls(
        projectId: 'book_track',
        projectName: 'book_track',
        device: FlutterRunDevice.macos,
      ),
    ]);
    addTearDown(registry.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsScreen(
          trigger: _trigger([_macosProject('book_track')]),
          localRunRegistry: registry,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LocalRunDetail), findsOneWidget);
    expect(find.byType(LocalRunScreen), findsNothing);
    expect(find.text('Hot reload'), findsOneWidget);
    expect(find.text('book_track · macOS'), findsOneWidget);
  });

  testWidgets('tapping Run on a wide homescreen opens that run in the pane', (
    tester,
  ) async {
    final bookTrack = _runningControls(
      projectId: 'book_track',
      projectName: 'book_track',
      device: FlutterRunDevice.macos,
    );
    final spendTrends = _idleControls(
      projectId: 'spend_trends',
      projectName: 'spend_trends',
      device: FlutterRunDevice.macos,
    );
    final registry = _StubLocalRunRegistry([bookTrack, spendTrends]);
    addTearDown(registry.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsScreen(
          trigger: _trigger([
            _macosProject('book_track'),
            _macosProject('spend_trends'),
          ]),
          localRunRegistry: registry,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('book_track · macOS'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('spend_trends')), findsOneWidget);

    await tester.tap(_runCellForProject('spend_trends', running: false));
    await tester.pump();

    expect(spendTrends.startCount, 1);
    expect(find.text('spend_trends · macOS'), findsOneWidget);
    expect(find.byType(LocalRunScreen), findsNothing);
    expect(find.text('Hot reload'), findsOneWidget);
  });

  testWidgets('compact homescreen still pushes the run screen', (tester) async {
    final registry = _StubLocalRunRegistry([
      _runningControls(
        projectId: 'book_track',
        projectName: 'book_track',
        device: FlutterRunDevice.macos,
      ),
    ]);
    addTearDown(registry.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(size: const Size(390, 844)),
            child: child!,
          );
        },
        home: ProjectsScreen(
          trigger: _trigger([_macosProject('book_track')]),
          localRunRegistry: registry,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LocalRunDetail), findsNothing);
    expect(find.text('Hot reload'), findsNothing);
    expect(find.byKey(const ValueKey<String>('book_track')), findsOneWidget);

    await tester.tap(_runCellForProject('book_track', running: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(LocalRunScreen), findsOneWidget);
    expect(find.text('Hot reload'), findsOneWidget);
  });

  testWidgets('run and deploy stay visible as separate panes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final registry = _StubLocalRunRegistry([
      _runningControls(
        projectId: 'book_track',
        projectName: 'book_track',
        device: FlutterRunDevice.macos,
      ),
    ]);
    addTearDown(registry.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsScreen(
          trigger: _trigger(
            [_macosProject('book_track')],
            activeJob: _runningIosJob('workouts'),
          ),
          localRunRegistry: registry,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LocalRunDetail), findsOneWidget);
    expect(find.text('Hot reload'), findsOneWidget);
    expect(find.text('book_track · macOS'), findsOneWidget);
    expect(find.byType(DeployQueuePanel), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('workouts'), findsOneWidget);
  });
}

Finder _runCellForProject(String projectId, {required bool running}) {
  return find.descendant(
    of: find.byKey(ValueKey<String>(projectId)),
    matching: find.byTooltip(running ? 'Run · Open' : 'Run · Debug'),
  );
}

WorkbenchProject _macosProject(String name) => WorkbenchProject(
  projectId: name,
  name: name,
  path: '/tmp/$name',
  platforms: {DeployPlatform.macos},
);

DeployJob _runningIosJob(String projectName) {
  return DeployJob(
    jobId: 'job-$projectName',
    projectId: projectName,
    projectName: projectName,
    platform: DeployPlatform.ios,
    force: false,
    status: DeployJobStatus.running,
    log: 'building…',
    createdAt: DateTime(2026, 1, 1),
  );
}

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
  var startCount = 0;
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
  }) async {
    startCount += 1;
    _state = LocalRunState(
      status: LocalRunStatus.running,
      log: 'started',
      readyForKeyCommands: true,
      projectId: project.projectId,
      projectName: project.name,
      projectPath: project.path,
      deviceKey: device.key,
      deviceLabel: device.label,
      flutterDeviceId: device.flutterDeviceId,
    );
    _updates.add(_state);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> hotReload() async {}

  @override
  Future<void> hotRestart() async {}

  @override
  Future<void> fullRestart() async {}
}
