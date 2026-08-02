/// Lifecycle of a macOS `flutter run` session.
enum MacosRunStatus {
  idle,
  starting,
  running,
  stopping,
  exited,
  failed;

  bool get isActive =>
      this == MacosRunStatus.starting ||
      this == MacosRunStatus.running ||
      this == MacosRunStatus.stopping;

  bool get canSendKeyCommands => this == MacosRunStatus.running;
}

/// Snapshot of the current `flutter run -d macos` session.
class MacosRunState {
  const MacosRunState({
    required this.status,
    required this.log,
    required this.readyForKeyCommands,
    this.projectId,
    this.projectName,
    this.projectPath,
    this.errorMessage,
    this.exitCode,
    this.reattached = false,
  });

  static const idle = MacosRunState(
    status: MacosRunStatus.idle,
    log: '',
    readyForKeyCommands: false,
  );

  final MacosRunStatus status;
  final String log;
  final bool readyForKeyCommands;
  final String? projectId;
  final String? projectName;
  final String? projectPath;
  final String? errorMessage;
  final int? exitCode;

  /// True when this session was reclaimed after a workbench restart (no stdin).
  final bool reattached;

  MacosRunState copyWith({
    MacosRunStatus? status,
    String? log,
    bool? readyForKeyCommands,
    String? projectId,
    String? projectName,
    String? projectPath,
    String? errorMessage,
    int? exitCode,
    bool? reattached,
    bool clearError = false,
    bool clearExitCode = false,
    bool clearProject = false,
  }) {
    return MacosRunState(
      status: status ?? this.status,
      log: log ?? this.log,
      readyForKeyCommands: readyForKeyCommands ?? this.readyForKeyCommands,
      projectId: clearProject ? null : (projectId ?? this.projectId),
      projectName: clearProject ? null : (projectName ?? this.projectName),
      projectPath: clearProject ? null : (projectPath ?? this.projectPath),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      exitCode: clearExitCode ? null : (exitCode ?? this.exitCode),
      reattached: reattached ?? this.reattached,
    );
  }
}

class MacosRunAlreadyActive implements Exception {
  const MacosRunAlreadyActive({
    required this.projectName,
    required this.statusName,
  });

  final String projectName;
  final String statusName;

  @override
  String toString() =>
      'A macOS run is already active: $projectName ($statusName)';
}

class DeployBlocksMacosRun implements Exception {
  const DeployBlocksMacosRun({
    required this.projectName,
    required this.statusName,
  });

  final String projectName;
  final String statusName;

  @override
  String toString() =>
      'Cannot start a macOS run while a deploy is active: '
      '$projectName ($statusName)';
}

class MacosRunBlocksDeploy implements Exception {
  const MacosRunBlocksDeploy({
    required this.projectName,
    required this.statusName,
  });

  final String projectName;
  final String statusName;

  @override
  String toString() =>
      'Cannot start a deploy while a macOS run is active: '
      '$projectName ($statusName)';
}
