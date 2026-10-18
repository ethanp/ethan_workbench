import 'deploy_checklist.dart';
import 'deploy_platform.dart';
import 'install.dart';

/// One run of a project on a platform.
///
/// [installStep] is performed by [install].
class const Deploy({
  required final DeployPlatform platform,
  required final bool force,
  required final InstallStep installStep,
}) {
  factory full({required DeployPlatform platform, bool force = false}) {
    return Deploy(
      platform: platform,
      force: force,
      installStep: InstallStep.pending(platform),
    );
  }

  /// A deploy whose install step runs against the build already on disk.
  factory retryingInstall({
    required DeployPlatform platform,
    bool force = false,
  }) {
    return Deploy(
      platform: platform,
      force: force,
      installStep: InstallStep.retrying(platform),
    );
  }

  factory fromJson(Map<String, dynamic> json) {
    final platform = DeployPlatform.fromName(json['platform'] as String);
    final force = json['force'] as bool? ?? false;
    final stepJson = json['installStep'] as Map<String, dynamic>?;
    final existingBuild = stepJson?['existingBuild'] as bool? ?? false;
    return Deploy(
      platform: platform,
      force: force,
      installStep: existingBuild
          ? InstallStep.retrying(platform)
          : InstallStep.pending(platform),
    );
  }

  /// Performs [installStep].
  Install get install => installStep.install;

  String get modeLabel {
    if (installStep.existingBuild) return 'Retry install';
    if (force) return 'Force rebuild';
    return 'Incremental deploy';
  }

  List<DeployChecklistItem> plannedChecklist() {
    if (installStep.existingBuild) {
      return [installStep.toChecklistItem(), DeployChecklist.recording];
    }
    return DeployChecklist.planned(platform: platform, force: force);
  }

  Map<String, dynamic> toJson() => {
    'platform': platform.name,
    'force': force,
    'installStep': installStep.toJson(),
  };
}
