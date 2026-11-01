import 'package:ethan_workbench/run/run_log_noise_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const meSimBuildOutput =
      'Running Xcode build...                                          \n'
      '-[WFIsolatedShortcutRunner init] Taking sandbox extensions for execution\n'
      '-[WFIsolatedShortcutRunner init]_block_invoke Sandbox extensions acquired\n'
      'Indexing for request: <WFToolKitIndexingRequest: 0x106d8c320>, '
      'changeset: .partial(updatedCount: 1 removedCount: 4)\n'
      'Indexed: 0\n'
      'Errored: 0\n'
      'Skipped: [:]\n'
      'Finished in 0.898751s\n'
      '-[WFIsolatedShortcutRunner unaliveProcess] Releasing sandbox extensions\n'
      'Xcode build done.                                           12.3s\n';

  group('RunLogNoiseFilter', () {
    test('drops Shortcuts sandbox and clean App Intents indexing lines', () {
      expect(
        RunLogNoiseFilter().meaningfulText(meSimBuildOutput),
        'Running Xcode build...                                          \n'
        'Xcode build done.                                           12.3s\n',
      );
    });

    test('drops noise split across chunks at any byte', () {
      for (var split = 1; split < meSimBuildOutput.length; split++) {
        final filter = RunLogNoiseFilter();
        final shown =
            filter.meaningfulText(meSimBuildOutput.substring(0, split)) +
            filter.meaningfulText(meSimBuildOutput.substring(split));
        expect(shown, RunLogNoiseFilter().meaningfulText(meSimBuildOutput));
      }
    });

    test('summarizes App Intents indexing that errored', () {
      expect(
        RunLogNoiseFilter().meaningfulText(
          'Indexing for request: <WFToolKitIndexingRequest: 0x1>\n'
          'Indexed: 3\n'
          'Errored: 2\n'
          'Skipped: [:]\n'
          'Finished in 1.5s\n',
        ),
        'App Intents indexing: 2 errored (1.5s)\n',
      );
    });

    test('shows a prompt without waiting for its newline', () {
      expect(
        RunLogNoiseFilter().meaningfulText('Running Xcode build...'),
        'Running Xcode build...',
      );
    });
  });
}
