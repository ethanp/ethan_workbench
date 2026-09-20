import 'package:ethan_ui/theme/e_layout.dart';
import 'package:ethan_workbench/projects/workbench_row_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'library row (no platforms) includes the after-identity gap and not a trailing cluster gap',
    () {
      const maxWidth = 400.0;
      final widths = WorkbenchRowSlotWidths.allocate(
        maxWidth: maxWidth,
        platformCount: 0,
        compact: false,
        showLineAge: true,
        showCommit: true,
      );

      expect(widths.identity, WorkbenchRowLayout.identityMaxWidth);
      expect(widths.lineAge, WorkbenchRowLayout.lineAgeWidth);
      expect(widths.commit, WorkbenchRowLayout.commitWidth);
      expect(
        widths.occupied(
          clusterGap: WorkbenchRowLayout.clusterGap,
          platformCount: 0,
        ),
        WorkbenchRowLayout.identityMaxWidth +
            ELayout.spaceMd +
            WorkbenchRowLayout.lineAgeWidth +
            WorkbenchRowLayout.clusterGap +
            WorkbenchRowLayout.commitWidth,
      );
    },
  );

  test('allocated slots never occupy more than the inner width', () {
    const budgets = [120.0, 200.0, 280.0, 327.0, 400.0, 800.0, 1400.0];
    for (final maxWidth in budgets) {
      for (final platformCount in [0, 1, 2]) {
        final widths = WorkbenchRowSlotWidths.allocate(
          maxWidth: maxWidth,
          platformCount: platformCount,
          compact: false,
          showLineAge: true,
          showCommit: true,
        );
        expect(
          widths.occupied(
            clusterGap: WorkbenchRowLayout.clusterGap,
            platformCount: platformCount,
          ),
          lessThanOrEqualTo(maxWidth),
          reason: 'platformCount=$platformCount maxWidth=$maxWidth',
        );
      }
    }
  });
}
