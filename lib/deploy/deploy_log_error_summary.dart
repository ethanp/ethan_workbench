/// Pulls Cursor-friendly failure hints from a deploy console log.
abstract final class DeployLogErrorSummary() {
  static final _errorLine = RegExp(
    r'(✗|error:|exception|failed|fatal|BUILD FAILED|Command failed|'
    r'Error \(Xcode\)|The following build commands failed|'
    r'Uncategorized \(Xcode\))',
    caseSensitive: false,
  );

  static final _genericCloser = RegExp(
    r'^(✗ Deploy (failed|crashed)|Command failed:|'
    r'Encountered error while building)',
    caseSensitive: false,
  );

  /// Short one-line hint for status JSON / Cursor prompts.
  static String? failureHint(String log) {
    final lines = _meaningfulLines(log);
    if (lines.isEmpty) return null;
    String? genericCloser;
    for (var index = lines.length - 1; index >= 0; index--) {
      final line = lines[index];
      if (!_errorLine.hasMatch(line)) continue;
      if (_genericCloser.hasMatch(line)) {
        genericCloser ??= line;
        continue;
      }
      return _ellipsisAt(_xcodebuildFailureReason(line), 240);
    }
    if (genericCloser != null) return _ellipsisAt(genericCloser, 240);
    return _ellipsisAt(lines.last, 240);
  }

  /// Trailing high-signal slice — prefer this over the full log first.
  static String errorTail(String log, {int maxLines = 40}) {
    final lines = _meaningfulLines(log);
    if (lines.isEmpty) return '';
    final start = lines.length > maxLines ? lines.length - maxLines : 0;
    final window = lines.sublist(start);

    final errorIndexes = <int>[];
    for (var index = 0; index < window.length; index++) {
      if (_errorLine.hasMatch(window[index])) errorIndexes.add(index);
    }
    if (errorIndexes.isEmpty) return window.join('\n');

    final firstError = errorIndexes.first;
    final contextStart = firstError > 5 ? firstError - 5 : 0;
    return window.sublist(contextStart).join('\n');
  }

  static List<String> _meaningfulLines(String log) {
    return [
      for (final line in log.split('\n'))
        if (line.trim().isNotEmpty) line.trimRight(),
    ];
  }

  static String _xcodebuildFailureReason(String line) {
    if (!line.contains('Failed to build workspace')) return line;
    const reasonSeparator = '.: ';
    final separatorIndex = line.lastIndexOf(reasonSeparator);
    if (separatorIndex == -1) return line;
    final reason = line
        .substring(separatorIndex + reasonSeparator.length)
        .trim();
    return reason.isEmpty ? line : reason;
  }

  static String _ellipsisAt(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars - 1)}…';
  }
}
