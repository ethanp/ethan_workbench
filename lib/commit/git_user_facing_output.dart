import 'dart:convert';

/// Git stderr / push stdout stripped to what a person committing would read.
abstract final class GitUserFacingOutput() {
  static String failureMessage(String raw) {
    final lines = [
      for (final line in LineSplitter.split(raw))
        if (_isFailureLine(line)) line.trimRight(),
    ];
    if (lines.isEmpty) return raw.trim();
    if (lines.length <= 24) return lines.join('\n');
    return lines.sublist(lines.length - 24).join('\n');
  }

  static List<String> pushLines(String stdout) {
    return [
      for (final line in LineSplitter.split(stdout))
        if (_isPushStatusLine(line)) line.trim(),
    ];
  }

  static bool _isFailureLine(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('hint:')) return false;
    return true;
  }

  static bool _isPushStatusLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('hint:')) return false;
    if (lower.startsWith('remote:')) return false;
    if (lower.contains('enumerating objects')) return false;
    if (lower.contains('counting objects')) return false;
    if (lower.contains('compressing objects')) return false;
    if (lower.contains('writing objects')) return false;
    if (lower.contains('resolving deltas')) return false;
    if (lower.contains('unpacked objects')) return false;
    if (lower.contains('delta compression')) return false;
    return true;
  }
}
