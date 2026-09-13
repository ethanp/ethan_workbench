import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import 'git_commit_notice.dart';
import 'git_user_facing_output.dart';
import 'uncommitted_change_counts.dart';
import 'uncommitted_file_diff.dart';

class const GitWorkingTreeFailed(
  final String message, {
  final bool commitCompleted = false,
}) implements Exception {
  @override
  String toString() => message;
}

/// Git checkout at [gitRoot]: uncommitted stats, diffs, commit, and push.
class GitWorkingTree.at(final String gitRoot) {
  Future<UncommittedChangeCounts> changeCounts() async {
    final porcelain = await _stdout(['status', '--porcelain']);
    if (porcelain.trim().isEmpty) return UncommittedChangeCounts.clean;

    var added = 0;
    var removed = 0;
    for (final row in LineSplitter.split(
      await _stdoutAllowFail(['diff', 'HEAD', '--numstat']),
    )) {
      if (row.isEmpty) continue;
      added += _numstatCount(row, 0);
      removed += _numstatCount(row, 1);
    }
    for (final relativePath in await _untrackedPaths()) {
      added += _textLineCount(relativePath);
    }
    return UncommittedChangeCounts(
      added: added,
      removed: removed,
      isClean: false,
    );
  }

  Future<List<UncommittedFileDiff>> fileDiffs() async {
    final files = [
      ...UncommittedPatch.fromGitDiff(
        await _stdoutAllowFail(['diff', 'HEAD', '--no-color']),
      ),
      for (final relativePath in await _untrackedPaths())
        _untrackedDiff(relativePath),
    ];
    files.sort((left, right) => left.path.compareTo(right.path));
    return files;
  }

  Future<bool> get hasPushRemote async => await pushRemoteName != null;

  Future<String?> get pushRemoteName async {
    final names = [
      for (final name in LineSplitter.split(await _stdout(['remote'])))
        if (name.trim().isNotEmpty) name.trim(),
    ];
    if (names.isEmpty) return null;
    if (names.contains('origin')) return 'origin';
    return names.first;
  }

  Future<void> commitAll({
    required String message,
    required bool push,
    required void Function(GitCommitNotice notice) onNotice,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      throw const GitWorkingTreeFailed('Write a commit message.');
    }
    onNotice(GitCommitNotice.info('Staging working tree'));
    await _stdout(['add', '.']);
    final stagedPaths = [
      for (final relativePath in LineSplitter.split(
        await _stdout(['diff', '--cached', '--name-only']),
      ))
        if (relativePath.trim().isNotEmpty) relativePath,
    ];
    if (stagedPaths.isEmpty) {
      throw const GitWorkingTreeFailed('Nothing to commit.');
    }
    onNotice(
      GitCommitNotice.info(
        stagedPaths.length == 1
            ? 'Staged 1 file'
            : 'Staged ${stagedPaths.length} files',
      ),
    );
    onNotice(GitCommitNotice.info('Creating commit'));
    final commitStdout = await _commitWithMessage(trimmed);
    onNotice(
      GitCommitNotice.success(_committedCaption(commitStdout, trimmed)),
    );
    final filesChanged = _filesChangedCaption(commitStdout);
    if (filesChanged != null) {
      onNotice(GitCommitNotice.info(filesChanged));
    }
    if (!push) return;
    await pushToRemote(onNotice: onNotice, afterCommit: true);
  }

  Future<void> pushToRemote({
    required void Function(GitCommitNotice notice) onNotice,
    bool afterCommit = false,
  }) async {
    final remote = await pushRemoteName;
    if (remote == null) {
      throw GitWorkingTreeFailed(
        'No remote to push to.',
        commitCompleted: afterCommit,
      );
    }
    final url = (await _stdout(['remote', 'get-url', remote])).trim();
    onNotice(GitCommitNotice.info('Pushing to ${_shortRemote(url)}'));
    final args = await _hasUpstream
        ? ['push']
        : ['push', '-u', remote, 'HEAD'];
    try {
      final stdout = await _stdout(args);
      for (final line in GitUserFacingOutput.pushLines(stdout)) {
        onNotice(GitCommitNotice.info(line));
      }
    } on GitWorkingTreeFailed catch (error) {
      throw GitWorkingTreeFailed(
        error.message,
        commitCompleted: afterCommit,
      );
    }
    final branch =
        (await _stdout(['rev-parse', '--abbrev-ref', 'HEAD'])).trim();
    onNotice(GitCommitNotice.success('Pushed $branch'));
  }

  UncommittedFileDiff _untrackedDiff(String relativePath) {
    final file = File(path.join(gitRoot, relativePath));
    final bytes = _readPrefix(file);
    if (bytes != null && _containsNul(bytes)) {
      return UncommittedFileDiff.untracked(
        relativePath: relativePath,
        contentLines: const [],
        isBinary: true,
      );
    }
    return UncommittedFileDiff.untracked(
      relativePath: relativePath,
      contentLines: _textLines(file),
      isBinary: false,
    );
  }

  Future<List<String>> _untrackedPaths() async {
    return [
      for (final relativePath in LineSplitter.split(
        await _stdout(['ls-files', '--others', '--exclude-standard']),
      ))
        if (relativePath.trim().isNotEmpty) relativePath,
    ];
  }

  int _textLineCount(String relativePath) {
    final file = File(path.join(gitRoot, relativePath));
    final bytes = _readPrefix(file);
    if (bytes == null) return 0;
    if (_containsNul(bytes)) return 0;
    return _textLines(file).length;
  }

  List<String> _textLines(File file) {
    try {
      return file.readAsLinesSync();
    } on FileSystemException {
      return const [];
    }
  }

  Uint8List? _readPrefix(File file) {
    try {
      final opened = file.openSync();
      try {
        final length = opened.lengthSync().clamp(0, 8192);
        return opened.readSync(length);
      } finally {
        opened.closeSync();
      }
    } on FileSystemException {
      return null;
    }
  }

  bool _containsNul(Uint8List bytes) {
    for (final byte in bytes) {
      if (byte == 0) return true;
    }
    return false;
  }

  int _numstatCount(String row, int fieldIndex) {
    final tabs = row.split('\t');
    if (tabs.length <= fieldIndex) return 0;
    if (tabs[fieldIndex] == '-') return 0;
    return int.tryParse(tabs[fieldIndex]) ?? 0;
  }

  Future<bool> get _hasUpstream async {
    final process = await Process.run(
      'git',
      ['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}'],
      workingDirectory: gitRoot,
    );
    return process.exitCode == 0;
  }

  String _committedCaption(String stdout, String message) {
    final subject = const LineSplitter().convert(message).first.trim();
    final header = _firstNonEmpty(stdout);
    final hashMatch = RegExp(r'\[.+?\s([0-9a-f]{7,})\]').firstMatch(header);
    if (hashMatch == null) return 'Committed — $subject';
    return 'Committed ${hashMatch.group(1)} — $subject';
  }

  String? _filesChangedCaption(String stdout) {
    for (final line in LineSplitter.split(stdout)) {
      final trimmed = line.trim();
      if (trimmed.contains('file changed') ||
          trimmed.contains('files changed')) {
        return trimmed;
      }
    }
    return null;
  }

  String _firstNonEmpty(String stdout) {
    for (final line in LineSplitter.split(stdout)) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return '';
  }

  String _shortRemote(String url) {
    var display = url.trim();
    if (display.endsWith('.git')) {
      display = display.substring(0, display.length - 4);
    }
    const sshPrefix = 'git@';
    if (display.startsWith(sshPrefix)) {
      return display.substring(sshPrefix.length).replaceFirst(':', '/');
    }
    const httpsPrefix = 'https://';
    if (display.startsWith(httpsPrefix)) {
      return display.substring(httpsPrefix.length);
    }
    const httpPrefix = 'http://';
    if (display.startsWith(httpPrefix)) {
      return display.substring(httpPrefix.length);
    }
    return display;
  }

  Future<String> _commitWithMessage(String message) async {
    final process = await Process.start(
      'git',
      ['commit', '-F', '-'],
      workingDirectory: gitRoot,
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(message);
    if (!message.endsWith('\n')) process.stdin.write('\n');
    await process.stdin.close();
    final exitCode = await process.exitCode;
    final stdoutText = await stdout;
    final stderrText = await stderr;
    if (exitCode != 0) {
      throw GitWorkingTreeFailed(
        GitUserFacingOutput.failureMessage(
          stderrText.trim().isNotEmpty ? stderrText : stdoutText,
        ),
      );
    }
    return stdoutText;
  }

  Future<String> _stdout(List<String> args) async {
    final process = await Process.run(
      'git',
      args,
      workingDirectory: gitRoot,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (process.exitCode != 0) {
      throw GitWorkingTreeFailed(
        GitUserFacingOutput.failureMessage(
          _commandFailureBody(process, args),
        ),
      );
    }
    return process.stdout as String;
  }

  Future<String> _stdoutAllowFail(List<String> args) async {
    try {
      return await _stdout(args);
    } on GitWorkingTreeFailed {
      return '';
    }
  }

  String _commandFailureBody(ProcessResult process, List<String> args) {
    final stderr = (process.stderr as String).trim();
    if (stderr.isNotEmpty) return stderr;
    final stdout = (process.stdout as String).trim();
    if (stdout.isNotEmpty) return stdout;
    return 'git ${args.join(' ')} failed (exit ${process.exitCode}).';
  }
}
