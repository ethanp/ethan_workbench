/// Drops simulator system chatter from `flutter run` output before it reaches
/// the run log. Works on whole lines; a partial line is held only while it
/// could still turn out to be noise, so prompts and spinners stay live.
class RunLogNoiseFilter() {
  /// Shortcuts' sandbox bookkeeping, e.g.
  /// `-[WFIsolatedShortcutRunner init] Taking sandbox extensions for execution`.
  static final _shortcutsRunnerLine = RegExp(r'^-\[WF\w+ ');

  /// Opens the App Intents indexing report printed when an app installs.
  static final _appIntentsIndexingStart = RegExp(r'^Indexing for request: ');
  static final _appIntentsIndexingCount = RegExp(
    r'^(Indexed|Errored|Skipped): ',
  );
  static final _appIntentsIndexingErrored = RegExp(r'^Errored: (\d+)');
  static final _appIntentsIndexingFinished = RegExp(r'^Finished in ([\d.]+)s');

  static const _noiseOpeners = ['-[WF', 'Indexing for request: '];

  String _heldPartialLine = '';
  bool _emittedStartOfCurrentLine = false;
  bool _inAppIntentsIndexing = false;
  int _appIntentsIndexingErrors = 0;

  void reset() {
    _heldPartialLine = '';
    _emittedStartOfCurrentLine = false;
    _inAppIntentsIndexing = false;
    _appIntentsIndexingErrors = 0;
  }

  /// The part of [chunk] worth showing; empty when it was all noise.
  String meaningfulText(String chunk) {
    final meaningful = StringBuffer();
    var remaining = chunk;
    while (remaining.isNotEmpty) {
      final newlineIndex = remaining.indexOf('\n');
      if (newlineIndex < 0) {
        meaningful.write(_partialLine(remaining));
        break;
      }
      meaningful.write(_completeLine(remaining.substring(0, newlineIndex + 1)));
      remaining = remaining.substring(newlineIndex + 1);
    }
    return meaningful.toString();
  }

  String _partialLine(String fragment) {
    if (_emittedStartOfCurrentLine) return fragment;
    final candidate = _heldPartialLine + fragment;
    if (_inAppIntentsIndexing || _couldOpenNoise(candidate)) {
      _heldPartialLine = candidate;
      return '';
    }
    _heldPartialLine = '';
    _emittedStartOfCurrentLine = true;
    return candidate;
  }

  String _completeLine(String lineEndingInNewline) {
    if (_emittedStartOfCurrentLine) {
      _emittedStartOfCurrentLine = false;
      return lineEndingInNewline;
    }
    final line = _heldPartialLine + lineEndingInNewline;
    _heldPartialLine = '';
    return _keptLine(line);
  }

  String _keptLine(String line) {
    if (_shortcutsRunnerLine.hasMatch(line)) return '';
    if (_appIntentsIndexingStart.hasMatch(line)) {
      _inAppIntentsIndexing = true;
      _appIntentsIndexingErrors = 0;
      return '';
    }
    if (!_inAppIntentsIndexing) return line;
    final erroredMatch = _appIntentsIndexingErrored.firstMatch(line);
    if (erroredMatch != null) {
      _appIntentsIndexingErrors = int.parse(erroredMatch.group(1)!);
    }
    if (_appIntentsIndexingCount.hasMatch(line)) return '';
    final finishedMatch = _appIntentsIndexingFinished.firstMatch(line);
    if (finishedMatch == null) return line;
    _inAppIntentsIndexing = false;
    if (_appIntentsIndexingErrors == 0) return '';
    return 'App Intents indexing: $_appIntentsIndexingErrors errored '
        '(${finishedMatch.group(1)}s)\n';
  }

  static bool _couldOpenNoise(String partialLine) => _noiseOpeners.any(
    (opener) =>
        partialLine.startsWith(opener) || opener.startsWith(partialLine),
  );
}
