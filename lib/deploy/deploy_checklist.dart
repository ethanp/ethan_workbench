import 'deploy_platform.dart';

enum DeployChecklistItemStatus {
  pending,
  active,
  done,
  skipped;

  static DeployChecklistItemStatus fromName(String name) {
    return DeployChecklistItemStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => DeployChecklistItemStatus.pending,
    );
  }
}

class DeployChecklistItem {
  final String id;
  final String label;
  final DeployChecklistItemStatus status;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  const DeployChecklistItem({
    required this.id,
    required this.label,
    required this.status,
    this.startedAt,
    this.finishedAt,
  });

  factory DeployChecklistItem.fromJson(Map<String, dynamic> json) {
    return DeployChecklistItem(
      id: json['id'] as String,
      label: json['label'] as String,
      status: DeployChecklistItemStatus.fromName(
        json['status'] as String? ?? DeployChecklistItemStatus.pending.name,
      ),
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String),
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.parse(json['finishedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'status': status.name,
    'startedAt': startedAt?.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
  };

  DeployChecklistItem asPending() => DeployChecklistItem(
    id: id,
    label: label,
    status: DeployChecklistItemStatus.pending,
  );

  DeployChecklistItem asActive({required DateTime at}) => DeployChecklistItem(
    id: id,
    label: label,
    status: DeployChecklistItemStatus.active,
    startedAt: at,
  );

  DeployChecklistItem asDone({required DateTime at}) {
    if (status == DeployChecklistItemStatus.done) return this;
    return DeployChecklistItem(
      id: id,
      label: label,
      status: DeployChecklistItemStatus.done,
      startedAt: startedAt,
      finishedAt: finishedAt ?? at,
    );
  }

  DeployChecklistItem asSkipped() => DeployChecklistItem(
    id: id,
    label: label,
    status: DeployChecklistItemStatus.skipped,
    startedAt: startedAt,
    finishedAt: finishedAt,
  );
}

abstract final class DeployChecklist {
  static const phasePrefix = 'DEPLOY_PHASE:';

  static List<DeployChecklistItem> planned({
    required DeployPlatform platform,
    required bool force,
  }) {
    final installLabel = switch (platform) {
      DeployPlatform.ios => 'Install on iPhone',
      DeployPlatform.macos => 'Install to Applications',
    };
    return [
      if (!force)
        const DeployChecklistItem(
          id: 'checking',
          label: 'Ensure app has changed',
          status: DeployChecklistItemStatus.pending,
        ),
      const DeployChecklistItem(
        id: 'resolving',
        label: 'Resolve dependencies',
        status: DeployChecklistItemStatus.pending,
      ),
      const DeployChecklistItem(
        id: 'building',
        label: 'Build app',
        status: DeployChecklistItemStatus.pending,
      ),
      DeployChecklistItem(
        id: 'installing',
        label: installLabel,
        status: DeployChecklistItemStatus.pending,
      ),
      const DeployChecklistItem(
        id: 'recording',
        label: 'Save deploy hash',
        status: DeployChecklistItemStatus.pending,
      ),
    ];
  }

  static List<DeployChecklistItem> activateFirst(
    List<DeployChecklistItem> items, {
    required DateTime at,
  }) {
    if (items.isEmpty) return items;
    return [items.first.asActive(at: at), ...items.skip(1)];
  }

  static List<DeployChecklistItem> applyPhase(
    List<DeployChecklistItem> items,
    String phaseId, {
    required DateTime at,
  }) {
    if (phaseId == 'skipped') {
      return [
        for (final item in items)
          if (item.id == 'checking') item.asDone(at: at) else item.asSkipped(),
      ];
    }
    if (phaseId == 'done') {
      return [
        for (final item in items)
          if (item.status == DeployChecklistItemStatus.pending ||
              item.status == DeployChecklistItemStatus.active)
            item.asDone(at: at)
          else
            item,
      ];
    }

    final targetIndex = items.indexWhere((item) => item.id == phaseId);
    if (targetIndex < 0) return items;

    return [
      for (var index = 0; index < items.length; index++)
        if (index < targetIndex)
          items[index].status == DeployChecklistItemStatus.done ||
                  items[index].status == DeployChecklistItemStatus.skipped
              ? items[index]
              : items[index].asDone(at: at)
        else if (index == targetIndex)
          items[index].asActive(at: at)
        else
          items[index].asPending(),
    ];
  }

  /// `3s`, `1m 3s`, `1h 2m 3s`.
  static String formatElapsed(Duration elapsed) {
    final totalSeconds = elapsed.abs().inSeconds;
    if (totalSeconds < 60) return '${totalSeconds}s';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      if (minutes == 0 && seconds == 0) return '${hours}h';
      if (seconds == 0) return '${hours}h ${minutes}m';
      return '${hours}h ${minutes}m ${seconds}s';
    }
    if (seconds == 0) return '${minutes}m';
    return '${minutes}m ${seconds}s';
  }
}
