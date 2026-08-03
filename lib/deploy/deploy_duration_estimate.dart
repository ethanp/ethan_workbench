import 'deploy_job.dart';
import 'deploy_platform.dart';
import 'deploy_run_record.dart';

/// Typical wall-clock duration from past successful deploys of one app/platform.
abstract final class DeployDurationEstimate {
  /// Median elapsed among recent successful runs for [projectId]/[platform].
  ///
  /// Prefers runs matching [force] when at least two such samples exist;
  /// otherwise uses all successful runs for that project/platform.
  static Duration? medianSuccessful({
    required List<DeployRunRecord> runs,
    required String projectId,
    required DeployPlatform platform,
    bool? force,
    int maxSamples = 12,
  }) {
    final forTarget = [
      for (final run in runs)
        if (run.projectId == projectId &&
            run.platform == platform &&
            run.status == DeployJobStatus.succeeded &&
            run.finishedAt != null)
          run,
    ];
    if (forTarget.isEmpty) return null;

    var samples = forTarget;
    if (force != null) {
      final forceMatched = [
        for (final run in forTarget)
          if (run.force == force) run,
      ];
      if (forceMatched.length >= 2) samples = forceMatched;
    }

    final durations = [
      for (final run in samples.take(maxSamples)) run.elapsed,
    ];
    if (durations.isEmpty) return null;

    durations.sort((left, right) => left.compareTo(right));
    final middle = durations.length ~/ 2;
    if (durations.length.isOdd) return durations[middle];
    return Duration(
      microseconds:
          (durations[middle - 1].inMicroseconds +
              durations[middle].inMicroseconds) ~/
          2,
    );
  }

  /// Typical duration minus elapsed since [startedAt]; zero when overdue.
  static Duration? remaining({
    required Duration typical,
    required DateTime startedAt,
    DateTime? now,
  }) {
    final elapsed = (now ?? DateTime.now()).difference(startedAt);
    final left = typical - elapsed;
    if (left.isNegative) return Duration.zero;
    return left;
  }
}
