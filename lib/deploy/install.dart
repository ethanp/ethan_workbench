import 'deploy.dart';
import 'deploy_checklist.dart';
import 'deploy_platform.dart';

/// The deploy step that puts the built app on the iPhone or into /Applications.
class const InstallStep({
  required final DeployPlatform platform,
  required final DeployChecklistItemStatus status,
  final DateTime? startedAt,
  final DateTime? finishedAt,

  /// This step installs the build already on disk.
  final bool existingBuild = false,
}) {
  static const phaseId = 'installing';

  factory pending(DeployPlatform platform) {
    return InstallStep(
      platform: platform,
      status: DeployChecklistItemStatus.pending,
    );
  }

  /// Perform the install again, against the build already on disk.
  factory retrying(DeployPlatform platform) {
    return InstallStep(
      platform: platform,
      status: DeployChecklistItemStatus.pending,
      existingBuild: true,
    );
  }

  static InstallStep? onChecklist({
    required List<DeployChecklistItem> checklist,
    required DeployPlatform platform,
  }) {
    for (final item in checklist) {
      if (item.id != phaseId) continue;
      return InstallStep(
        platform: platform,
        status: item.status,
        startedAt: item.startedAt,
        finishedAt: item.finishedAt,
      );
    }
    return null;
  }

  String get label => switch (platform) {
    DeployPlatform.ios => 'Install on iPhone',
    DeployPlatform.macos => 'Install to Applications',
  };

  bool get failed => status == DeployChecklistItemStatus.failed;

  /// Performs this step.
  Install get install => Install(step: this);

  DeployChecklistItem toChecklistItem() {
    return DeployChecklistItem(
      id: phaseId,
      label: label,
      status: status,
      startedAt: startedAt,
      finishedAt: finishedAt,
    );
  }

  Map<String, dynamic> toJson() => {'existingBuild': existingBuild};
}

/// Performs an [InstallStep].
class const Install({required final InstallStep step}) {
  static const _scriptArgument = '--from-install';

  /// When [step] failed, a deploy that performs only that install.
  Deploy? retry({required bool force}) {
    if (!step.failed) return null;
    return Deploy.retryingInstall(platform: step.platform, force: force);
  }

  void addScriptArguments(List<String> arguments) {
    if (!step.existingBuild) return;
    arguments.add(_scriptArgument);
  }

  String get scriptSuffix => step.existingBuild ? ' $_scriptArgument' : '';

  String get logDetail => 'retry install';
}
