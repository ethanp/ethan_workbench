import 'package:ethan_ui/ethan_ui.dart';

import 'flutter_run_exception.dart';

/// Lifecycle of a local `flutter run` session.
enum LocalRunStatus {
  idle(chipLabel: 'idle', chipTone: EStatusTone.muted, actionSubtitle: null),
  starting(
    chipLabel: 'starting',
    chipTone: EStatusTone.accent,
    actionSubtitle: 'Starting…',
  ),
  running(
    chipLabel: 'running',
    chipTone: EStatusTone.success,
    actionSubtitle: 'Open',
  ),
  stopping(
    chipLabel: 'stopping',
    chipTone: EStatusTone.warning,
    actionSubtitle: 'Stopping…',
  ),
  exited(chipLabel: 'exited', chipTone: EStatusTone.muted, actionSubtitle: null),
  failed(chipLabel: 'failed', chipTone: EStatusTone.danger, actionSubtitle: null);

  const LocalRunStatus({
    required this.chipLabel,
    required this.chipTone,
    required this.actionSubtitle,
  });

  final String chipLabel;
  final EStatusTone chipTone;

  /// Fixed plate subtitle while active; null means use the idle caption.
  final String? actionSubtitle;

  bool get isActive =>
      this == LocalRunStatus.starting ||
      this == LocalRunStatus.running ||
      this == LocalRunStatus.stopping;

  bool get canSendKeyCommands => this == LocalRunStatus.running;

  String subtitleGivenIdle(String idleSubtitle) =>
      actionSubtitle ?? idleSubtitle;
}

/// Snapshot of the current local `flutter run` session.
class LocalRunState {
  const LocalRunState({
    required this.status,
    required this.log,
    required this.readyForKeyCommands,
    this.projectId,
    this.projectName,
    this.projectPath,
    this.deviceKey,
    this.deviceLabel,
    this.flutterDeviceId,
    this.errorMessage,
    this.exitCode,
    this.reattached = false,
    this.flutterException,
  });

  static const idle = LocalRunState(
    status: LocalRunStatus.idle,
    log: '',
    readyForKeyCommands: false,
  );

  final LocalRunStatus status;
  final String log;
  final bool readyForKeyCommands;
  final String? projectId;
  final String? projectName;
  final String? projectPath;

  /// [FlutterRunDevice.key] for the active target (`macos`, `meSim`, …).
  final String? deviceKey;
  final String? deviceLabel;

  /// Resolved `-d` argument (UDID or `macos`).
  final String? flutterDeviceId;
  final String? errorMessage;
  final int? exitCode;

  /// True when this session was reclaimed after a workbench restart (no stdin).
  final bool reattached;

  /// Latest high-signal Flutter EXCEPTION CAUGHT dump, if any.
  final FlutterRunException? flutterException;

  factory LocalRunState.fromJson(Map<String, dynamic> json) {
    final exceptionJson = json['flutterException'];
    return LocalRunState(
      status: LocalRunStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => LocalRunStatus.idle,
      ),
      log: json['log'] as String? ?? '',
      readyForKeyCommands: json['readyForKeyCommands'] as bool? ?? false,
      projectId: json['projectId'] as String?,
      projectName: json['projectName'] as String?,
      projectPath: json['projectPath'] as String?,
      deviceKey: json['deviceKey'] as String?,
      deviceLabel: json['deviceLabel'] as String?,
      flutterDeviceId: json['flutterDeviceId'] as String?,
      errorMessage: json['errorMessage'] as String?,
      exitCode: json['exitCode'] as int?,
      reattached: json['reattached'] as bool? ?? false,
      flutterException: exceptionJson is Map<String, dynamic>
          ? FlutterRunException.fromJson(exceptionJson)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'log': log,
    'readyForKeyCommands': readyForKeyCommands,
    'projectId': projectId,
    'projectName': projectName,
    'projectPath': projectPath,
    'deviceKey': deviceKey,
    'deviceLabel': deviceLabel,
    'flutterDeviceId': flutterDeviceId,
    'errorMessage': errorMessage,
    'exitCode': exitCode,
    'reattached': reattached,
    'flutterException': flutterException?.toJson(),
  };

  LocalRunState copyWith({
    LocalRunStatus? status,
    String? log,
    bool? readyForKeyCommands,
    String? projectId,
    String? projectName,
    String? projectPath,
    String? deviceKey,
    String? deviceLabel,
    String? flutterDeviceId,
    String? errorMessage,
    int? exitCode,
    bool? reattached,
    FlutterRunException? flutterException,
    bool clearError = false,
    bool clearExitCode = false,
    bool clearProject = false,
    bool clearFlutterException = false,
  }) {
    return LocalRunState(
      status: status ?? this.status,
      log: log ?? this.log,
      readyForKeyCommands: readyForKeyCommands ?? this.readyForKeyCommands,
      projectId: clearProject ? null : (projectId ?? this.projectId),
      projectName: clearProject ? null : (projectName ?? this.projectName),
      projectPath: clearProject ? null : (projectPath ?? this.projectPath),
      deviceKey: clearProject ? null : (deviceKey ?? this.deviceKey),
      deviceLabel: clearProject ? null : (deviceLabel ?? this.deviceLabel),
      flutterDeviceId: clearProject
          ? null
          : (flutterDeviceId ?? this.flutterDeviceId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      exitCode: clearExitCode ? null : (exitCode ?? this.exitCode),
      reattached: reattached ?? this.reattached,
      flutterException: clearFlutterException
          ? null
          : (flutterException ?? this.flutterException),
    );
  }
}

class LocalRunAlreadyActive implements Exception {
  const LocalRunAlreadyActive({
    required this.projectName,
    required this.statusName,
  });

  final String projectName;
  final String statusName;

  @override
  String toString() =>
      'A local run is already active: $projectName ($statusName)';
}

class DeployBlocksLocalRun implements Exception {
  const DeployBlocksLocalRun({
    required this.projectName,
    required this.statusName,
  });

  final String projectName;
  final String statusName;

  @override
  String toString() =>
      'Cannot start a local run while a deploy is active: '
      '$projectName ($statusName)';
}

class LocalRunBlocksDeploy implements Exception {
  const LocalRunBlocksDeploy({
    required this.projectName,
    required this.statusName,
  });

  final String projectName;
  final String statusName;

  @override
  String toString() =>
      'Cannot start a deploy while a local run is active: '
      '$projectName ($statusName)';
}
