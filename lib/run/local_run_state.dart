/// Lifecycle of a local `flutter run` session.
enum LocalRunStatus {
  idle,
  starting,
  running,
  stopping,
  exited,
  failed;

  bool get isActive =>
      this == LocalRunStatus.starting ||
      this == LocalRunStatus.running ||
      this == LocalRunStatus.stopping;

  bool get canSendKeyCommands => this == LocalRunStatus.running;
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
    bool clearError = false,
    bool clearExitCode = false,
    bool clearProject = false,
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
