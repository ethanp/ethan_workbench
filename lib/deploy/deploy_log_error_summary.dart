/// Pulls Cursor-friendly failure hints from a deploy console log.
abstract final class DeployLogErrorSummary {
  static final _errorLine = RegExp(
    r'(✗|error:|exception|failed|fatal|BUILD FAILED|Command failed|'
    r'Error \(Xcode\)|The following build commands failed)',
    caseSensitive: false,
  );

  /// Short one-line hint for status JSON / Cursor prompts.
  static String? failureHint(String log) {
    final lines = _meaningfulLines(log);
    if (lines.isEmpty) return null;
    for (var index = lines.length - 1; index >= 0; index--) {
      final line = lines[index];
      if (_errorLine.hasMatch(line)) return _clip(line, 240);
    }
    return _clip(lines.last, 240);
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

  static String _clip(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars - 1)}…';
  }
}
