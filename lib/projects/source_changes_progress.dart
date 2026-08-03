/// How far a source-change scan has gotten across deployable projects.
class SourceChangesProgress {
  const SourceChangesProgress({
    required this.completed,
    required this.total,
    this.projectName,
  });

  final int completed;
  final int total;
  final String? projectName;

  double? get fraction {
    if (total <= 0) return null;
    return (completed / total).clamp(0.0, 1.0);
  }

  String get caption {
    if (total <= 0) return 'Checking…';
    return '$completed of $total';
  }
}
