import 'dart:typed_data';

import 'package:ethan_workbench/commit/commit_diff_pane.dart';
import 'package:ethan_workbench/commit/uncommitted_file_diff.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('updated golden shows the before and after images', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommitDiffPane(
            files: [
              UncommittedFileDiff(
                path: 'test/goldens/day_pace.png',
                added: 0,
                removed: 0,
                lines: const [],
                isBinary: true,
                image: UncommittedImagePreview(
                  before: _onePixelPng,
                  after: _onePixelPng,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('test/goldens/day_pace.png'), findsOneWidget);
    expect(find.text('updated image'), findsOneWidget);
    expect(find.text('before'), findsOneWidget);
    expect(find.text('after'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.text('Binary file'), findsNothing);
  });
}

final _onePixelPng = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde, 0x00, 0x00, 0x00,
  0x0c, 0x49, 0x44, 0x41, 0x54, 0x08, 0xd7, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xfe, 0x02, 0xfe, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);
