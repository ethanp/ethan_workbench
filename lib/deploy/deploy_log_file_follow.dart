import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Appends unseen bytes from a growing deploy log file (survives reclaim).
class DeployLogFileFollow {
  DeployLogFileFollow({
    required this.logPath,
    required this.onChunk,
    int startOffset = 0,
    this.pollInterval = const Duration(milliseconds: 200),
  }) : _offset = startOffset < 0 ? 0 : startOffset;

  final String logPath;
  final void Function(String chunk) onChunk;
  final Duration pollInterval;

  int _offset;
  Timer? _timer;
  bool _stopped = false;

  /// Catch up once, then poll for new bytes until [stop].
  Future<void> start() async {
    await _readNewBytes();
    if (_stopped) return;
    _timer = Timer.periodic(pollInterval, (_) {
      unawaited(_readNewBytes());
    });
  }

  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    await _readNewBytes();
  }

  Future<void> _readNewBytes() async {
    final file = File(logPath);
    if (!await file.exists()) return;
    final length = await file.length();
    if (length <= _offset) return;
    final randomAccess = await file.open();
    try {
      await randomAccess.setPosition(_offset);
      final bytes = await randomAccess.read(length - _offset);
      _offset = length;
      if (bytes.isEmpty) return;
      onChunk(utf8.decode(Uint8List.fromList(bytes), allowMalformed: true));
    } finally {
      await randomAccess.close();
    }
  }
}

/// Merge [fileContent] onto [existing] without duplicating a shared suffix/prefix.
String mergeDeployLogWithFile(String existing, String fileContent) {
  if (fileContent.isEmpty) return existing;
  if (existing.isEmpty) return fileContent;
  if (existing.endsWith(fileContent)) return existing;
  if (fileContent.startsWith(existing)) return fileContent;

  final maxOverlap = existing.length < fileContent.length
      ? existing.length
      : fileContent.length;
  for (var overlap = maxOverlap; overlap > 0; overlap--) {
    if (fileContent.startsWith(existing.substring(existing.length - overlap))) {
      return existing + fileContent.substring(overlap);
    }
  }
  return existing + fileContent;
}
