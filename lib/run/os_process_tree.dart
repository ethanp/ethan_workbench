import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A Unix process and its descendants, addressed by pid.
class const OsProcessTree(final int pid) {
  Future<bool> get isAlive async {
    if (pid <= 0) return false;
    final result = await Process.run('kill', ['-0', '$pid']);
    return result.exitCode == 0;
  }

  /// SIGTERM the tree, wait, then SIGKILL if needed (no-op if already dead).
  ///
  /// Descendants are collected first so a grandchild (xcodebuild under
  /// deploy.rb, a Mac app under `flutter run`) is signaled even after the
  /// parent exits and the child is reparented.
  Future<void> killTillExit() async {
    final descendants = await _descendantPids();
    if (!await isAlive && descendants.isEmpty) return;
    _signalTree(descendants, ProcessSignal.sigterm);
    await _waitUntilExit(descendants);
  }

  Future<void> _waitUntilExit(List<int> descendants) async {
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    while (DateTime.now().isBefore(deadline)) {
      if (!await isAlive && !await _anyAlive(descendants)) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    _signalTree(descendants, ProcessSignal.sigkill);
  }

  void _signalTree(List<int> descendants, ProcessSignal signal) {
    for (final descendant in descendants.reversed) {
      _signal(descendant, signal);
    }
    _signal(pid, signal);
  }

  Future<bool> _anyAlive(List<int> pids) async {
    for (final candidate in pids) {
      if (await OsProcessTree(candidate).isAlive) return true;
    }
    return false;
  }

  Future<List<int>> _descendantPids() async {
    final descendants = <int>[];
    final pending = await _childPids(pid);
    while (pending.isNotEmpty) {
      final childPid = pending.removeLast();
      descendants.add(childPid);
      pending.addAll(await _childPids(childPid));
    }
    return descendants;
  }

  Future<List<int>> _childPids(int parentPid) async {
    final result = await Process.run('pgrep', ['-P', '$parentPid']);
    if (result.exitCode != 0) return const [];
    final stdoutText = result.stdout;
    if (stdoutText is! String) return const [];
    return [
      for (final line in const LineSplitter().convert(stdoutText))
        if (int.tryParse(line.trim()) case final int childPid) childPid,
    ];
  }

  void _signal(int targetPid, ProcessSignal signal) {
    if (targetPid <= 0) return;
    try {
      Process.killPid(targetPid, signal);
    } on ProcessException {
      // Already exited.
    }
  }
}

extension AsOsProcessTree on int {
  OsProcessTree get asOsProcessTree => OsProcessTree(this);
}

/// Polls a pid until it dies (reattach-without-process fallback).
class PidLivenessWatch() {
  Timer? _timer;

  void watch(int pid, {required Future<void> Function() onDead}) {
    cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (await pid.asOsProcessTree.isAlive) return;
      cancel();
      await onDead();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
