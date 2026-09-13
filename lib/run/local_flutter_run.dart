import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../tooling/flutter_tool_environment.dart';
import 'flutter_run_exception.dart';
import 'os_process_tree.dart';

/// Interprets `flutter run` / `flutter attach` log text.
abstract final class FlutterRunOutput() {
  static final _vmServiceUriPattern = RegExp(
    r'(?:A Dart VM Service|The Dart VM service is available|'
    r'An Observatory debugger and profiler).*?(https?://\S+)',
    caseSensitive: false,
  );

  static final _exceptionHeaderPattern = RegExp(
    r'EXCEPTION CAUGHT BY\s+(.+?)\s*╞',
    caseSensitive: false,
  );

  static final _boxRuleLinePattern = RegExp(r'^═{8,}\s*$', multiLine: true);

  static final _assertionThrownPattern = RegExp(
    r'The following (?:assertion|exception|FlutterError|_FlutterError) '
    r'was thrown (.+):\n(.+)',
    caseSensitive: false,
  );

  static final _appStackFramePattern = RegExp(
    r'^\s*#\d+\s+(\S+)\s+\((package:(?!flutter(?:_test)?/)[^)]+)\)',
    multiLine: true,
  );

  static final _eventPattern = RegExp(
    r'^Event:\s*\n\s*(.+)$',
    multiLine: true,
  );

  static final _targetPattern = RegExp(
    r'^Target:\s*\n\s*(.+)$',
    multiLine: true,
  );

  static final _errorCausingWidgetPattern = RegExp(
    r'The relevant error-causing widget was:\s*\n'
    r'\s*([A-Za-z_][A-Za-z0-9_]*)\s*\n'
    r'\s*\1:(file://\S+)',
    multiLine: true,
  );

  static final _creatorBlockPattern = RegExp(
    r'^\s*creator:\s*(.+?)(?=\n\s*(?:parentData|constraints|size|This RenderObject)|\n\n)',
    multiLine: true,
    dotAll: true,
  );

  static final _constraintsPattern = RegExp(
    r'^\s*constraints:\s*(.+)$',
    multiLine: true,
  );

  static final _sizePattern = RegExp(r'^\s*size:\s*(.+)$', multiLine: true);

  static final _followOnPattern = RegExp(
    r'Another exception was thrown:\s*(.+)$',
    multiLine: true,
  );

  /// How much trailing log to scan for dumps that arrive across chunks.
  static const exceptionScanWindowChars = 16000;

  static const _maxCreatorAncestors = 8;

  /// Hot-restart / hot-reload completion banners (also highlighted in the log).
  ///
  /// Exceptions before the last match belong to a prior app generation.
  static final sessionResetPattern = RegExp(
    r'Restarted application in .+$|'
    r'Reloaded \d+ of \d+ libraries in .+$',
    multiLine: true,
  );

  /// Index to begin scanning for EXCEPTION CAUGHT dumps.
  static int exceptionScanStart(String logText, {int floor = 0}) {
    var start = floor < 0 ? 0 : floor;
    if (start > logText.length) start = logText.length;
    for (final match in sessionResetPattern.allMatches(logText)) {
      if (match.end > start) start = match.end;
    }
    return start;
  }

  static bool looksReady(String text) {
    return text.contains('Flutter run key commands') ||
        text.contains('A Dart VM Service') ||
        text.contains('Flutter DevTools') ||
        text.contains('To hot restart') ||
        text.contains('Syncing files to device');
  }

  static String? vmServiceUriFrom(String text) {
    final match = _vmServiceUriPattern.firstMatch(text);
    if (match == null) return null;
    var uri = match.group(1)!;
    // Flutter sometimes trails the URL with punctuation.
    while (uri.endsWith('.') || uri.endsWith(')') || uri.endsWith(',')) {
      uri = uri.substring(0, uri.length - 1);
    }
    return uri;
  }

  /// Parses the newest high-signal EXCEPTION CAUGHT dump from [logText].
  ///
  /// [floor] ignores earlier log (e.g. cleared on hot restart). Completion
  /// banners like `Restarted application in …` also advance the scan start.
  static FlutterRunException? exceptionFrom(String logText, {int floor = 0}) {
    if (logText.isEmpty) return null;
    final scanStart = exceptionScanStart(logText, floor: floor);
    final scannable = scanStart >= logText.length
        ? ''
        : logText.substring(scanStart);
    if (scannable.isEmpty) return null;
    final window = scannable.length <= exceptionScanWindowChars
        ? scannable
        : scannable.substring(scannable.length - exceptionScanWindowChars);

    final dump = _lastExceptionDump(window);
    if (dump == null) return null;
    final dumpBody = dump.body;
    final afterDump = dump.after;

    final library = dump.library;
    final widgetMatch = _errorCausingWidgetPattern.firstMatch(dumpBody);
    final creatorMatch = _creatorBlockPattern.firstMatch(dumpBody);
    final constraintsMatch = _constraintsPattern.firstMatch(dumpBody);
    final sizeMatch = _sizePattern.firstMatch(dumpBody);
    final assertionMatch = _assertionThrownPattern.firstMatch(dumpBody);
    final appFrameMatch = _appStackFramePattern.firstMatch(dumpBody);
    final eventMatch = _eventPattern.firstMatch(dumpBody);
    final targetMatch = _targetPattern.firstMatch(dumpBody);
    final followOnMatch = _followOnPattern.firstMatch(afterDump);

    final widget = widgetMatch?.group(1)?.trim();
    var fileUri = widgetMatch?.group(2)?.trim();
    if (fileUri != null) {
      while (fileUri!.endsWith('.') ||
          fileUri.endsWith(')') ||
          fileUri.endsWith(',')) {
        fileUri = fileUri.substring(0, fileUri.length - 1);
      }
    }

    final creatorChain = _normalizeCreatorChain(creatorMatch?.group(1));
    final constraints = constraintsMatch?.group(1)?.trim();
    final size = sizeMatch?.group(1)?.trim();
    final followOn = followOnMatch?.group(1)?.trim();
    final thrownDuring = assertionMatch?.group(1)?.trim();
    final assertion = assertionMatch?.group(2)?.trim();
    final appFrameSymbol = appFrameMatch?.group(1)?.trim();
    final packageUri = appFrameMatch?.group(2)?.trim();
    final event = eventMatch?.group(1)?.trim();
    final target = targetMatch?.group(1)?.trim();

    final parsed = FlutterRunException(
      library: library.isEmpty ? null : library,
      widget: widget?.isEmpty == true ? null : widget,
      fileUri: fileUri?.isEmpty == true ? null : fileUri,
      packageUri: packageUri?.isEmpty == true ? null : packageUri,
      appFrameSymbol: appFrameSymbol?.isEmpty == true ? null : appFrameSymbol,
      thrownDuring: thrownDuring?.isEmpty == true ? null : thrownDuring,
      assertion: assertion?.isEmpty == true ? null : assertion,
      event: event?.isEmpty == true ? null : event,
      target: target?.isEmpty == true ? null : target,
      creatorChain: creatorChain,
      constraints: constraints?.isEmpty == true ? null : constraints,
      size: size?.isEmpty == true ? null : size,
      followOn: followOn?.isEmpty == true ? null : followOn,
    );
    if (!parsed.hasSignal) return null;
    return parsed;
  }

  static _ExceptionDumpSlice? _lastExceptionDump(String window) {
    final headers = _exceptionHeaderPattern.allMatches(window).toList();
    if (headers.isEmpty) return null;
    final header = headers.last;
    final headerLineEnd = window.indexOf('\n', header.end);
    if (headerLineEnd < 0) return null;
    final rest = window.substring(headerLineEnd + 1);
    final closer = _boxRuleLinePattern.firstMatch(rest);
    final nextHeader = _exceptionHeaderPattern.firstMatch(rest);
    var bodyEnd = rest.length;
    if (closer != null && closer.start < bodyEnd) {
      bodyEnd = closer.start;
    }
    if (nextHeader != null && nextHeader.start < bodyEnd) {
      bodyEnd = nextHeader.start;
    }
    return _ExceptionDumpSlice(
      library: header.group(1)?.trim() ?? '',
      body: rest.substring(0, bodyEnd),
      after: rest.substring(bodyEnd),
    );
  }

  static String? _normalizeCreatorChain(String? raw) {
    if (raw == null) return null;
    var chain = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (chain.isEmpty) return null;
    // Drop Flutter's truncation marker and anything after.
    final ellipsisIndex = chain.indexOf('← ⋯');
    if (ellipsisIndex >= 0) {
      chain = chain.substring(0, ellipsisIndex).trim();
    }
    final asciiEllipsis = chain.indexOf('← ...');
    if (asciiEllipsis >= 0) {
      chain = chain.substring(0, asciiEllipsis).trim();
    }
    while (chain.endsWith('←')) {
      chain = chain.substring(0, chain.length - 1).trim();
    }
    final ancestors = chain
        .split('←')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .take(_maxCreatorAncestors)
        .toList();
    if (ancestors.isEmpty) return null;
    return ancestors.join(' ← ');
  }
}

class const _ExceptionDumpSlice({
  required final String library,
  required final String body,
  required final String after,
});

/// One `flutter run` / `flutter attach` process (stdin, merged output, quit).
class LocalFlutterRun._(final Process _process) {
  final int pid = _process.pid;

  /// Merged stdout + stderr as text chunks.
  final Stream<String> output = _mergeOutput(_process);

  static Future<LocalFlutterRun> start({
    required String projectPath,
    required String deviceId,
  }) async {
    final process = await Process.start(
      'flutter',
      ['run', '-d', deviceId],
      workingDirectory: projectPath,
      environment: _flutterEnvironment(),
      runInShell: false,
    );
    return LocalFlutterRun._(process);
  }

  /// Reattach hot-reload control to an already-running debug app.
  static Future<LocalFlutterRun> attach({
    required String projectPath,
    required String deviceId,
    String? vmServiceUri,
  }) async {
    final arguments = <String>['attach', '-d', deviceId];
    if (vmServiceUri != null && vmServiceUri.isNotEmpty) {
      arguments.addAll(['--debug-uri', vmServiceUri]);
    }
    final process = await Process.start(
      'flutter',
      arguments,
      workingDirectory: projectPath,
      environment: _flutterEnvironment(),
      runInShell: false,
    );
    return LocalFlutterRun._(process);
  }

  Future<void> sendKey(String key) async {
    _process.stdin.write('$key\n');
    await _process.stdin.flush();
  }

  /// Graceful quit: stdin `q`, then SIGTERM tree, then SIGKILL. Returns exit code.
  Future<int> quit() async {
    try {
      _process.stdin.write('q\n');
      await _process.stdin.flush();
    } catch (_) {
      // Process may already be closing / stdin detached.
    }
    try {
      return await _process.exitCode.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      await killTreeTillExit();
      return await _process.exitCode;
    }
  }

  Future<int> waitForExit() => _process.exitCode;

  /// Signal this process tree and wait until it is gone.
  Future<void> killTreeTillExit() => pid.asOsProcessTree.killTillExit();

  static Stream<String> _mergeOutput(Process process) {
    return Stream<String>.multi((controller) {
      late final StreamSubscription<List<int>> stdoutSubscription;
      late final StreamSubscription<List<int>> stderrSubscription;

      void forward(List<int> bytes) {
        if (controller.isClosed) return;
        controller.add(utf8.decode(bytes, allowMalformed: true));
      }

      stdoutSubscription = process.stdout.listen(
        forward,
        onError: controller.addError,
      );
      stderrSubscription = process.stderr.listen(
        forward,
        onError: controller.addError,
      );

      controller.onCancel = () async {
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();
      };
    });
  }

  static Map<String, String> _flutterEnvironment() {
    final environment = flutterToolEnvironment();
    final path = environment['PATH'] ?? '';
    const brewBin = '/opt/homebrew/bin';
    const localBin = '/usr/local/bin';
    if (!path.contains(brewBin) || !path.contains(localBin)) {
      environment['PATH'] = '$brewBin:$localBin:$path';
    }
    return environment;
  }
}
