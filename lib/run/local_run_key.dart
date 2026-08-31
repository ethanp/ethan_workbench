/// Identity of one concurrent local `flutter run` (project + device).
class const LocalRunKey({
  required final String projectId,
  required final String deviceKey,
}) {
  /// Filesystem-safe fragment for persistence and Cursor mirror names.
  String get fileName =>
      '${_asFilesystemSafe(projectId)}__${_asFilesystemSafe(deviceKey)}';

  static String _asFilesystemSafe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  @override
  bool operator ==(Object other) =>
      other is LocalRunKey &&
      other.projectId == projectId &&
      other.deviceKey == deviceKey;

  @override
  int get hashCode => Object.hash(projectId, deviceKey);
}
