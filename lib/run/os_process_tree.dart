import 'dart:async';
import 'dart:io';

/// A Unix process and its descendants, addressed by pid.
class OsProcessTree {
  const OsProcessTree(this.pid);

  final int pid;

  Future<bool> get isAlive async {
    if (pid <= 0) return false;
    final result = await Process.run('kill', ['-0', '$pid']);
    return result.exitCode == 0;
  }

  /// SIGTERM the tree, wait, then SIGKILL if needed (no-op if already dead).
  Future<void> killTillExit() async {
    if (!await isAlive) return;
    await _signalTerm();
    await _waitUntilExit();
  }

  Future<void> _signalTerm() async {
    // Child macos app may outlive `flutter run` if we only signal the parent.
    await Process.run('pkill', ['-P', '$pid']);
    Process.killPid(pid, ProcessSignal.sigterm);
  }

  Future<void> _waitUntilExit() async {
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    while (DateTime.now().isBefore(deadline)) {
      if (!await isAlive) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    Process.killPid(pid, ProcessSignal.sigkill);
    await Process.run('pkill', ['-9', '-P', '$pid']);
  }
}

extension AsOsProcessTree on int {
  OsProcessTree get asOsProcessTree => OsProcessTree(this);
}
