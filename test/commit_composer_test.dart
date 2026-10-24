import 'package:ethan_workbench/commit/commit_composer.dart';
import 'package:ethan_workbench/commit/commit_diff_pane.dart';
import 'package:ethan_workbench/commit/git_commit_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('commit log keeps Done on screen in a short body', (tester) async {
    final messageController = TextEditingController(
      text: 'features: popover and chart legend',
    );
    addTearDown(messageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 520,
            width: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(child: CommitDiffPane(files: [])),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: CommitComposer(
                    messageController: messageController,
                    notices: [
                      for (var index = 0; index < 12; index++)
                        GitCommitNotice.info('Commit notice $index'),
                    ],
                    actionLabel: 'Done',
                    actionEnabled: true,
                    messageEnabled: false,
                    running: false,
                    onSubmit: () {},
                    onMessageChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Working tree is clean'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });
}
