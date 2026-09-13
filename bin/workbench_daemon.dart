import 'dart:io';

/// Prefer [scripts/workbench-daemon] / `workbench daemon start`.
void main() {
  stderr.writeln(
    'Start the workbench daemon with:\n'
    '  Flutter/ethan_workbench/scripts/workbench daemon start',
  );
}
