import 'package:ethan_workbench/commit/uncommitted_change_counts.dart';
import 'package:ethan_workbench/commit/uncommitted_file_diff.dart';
import 'package:ethan_workbench/commit/git_user_facing_output.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('caption is +added / -removed for dirty line edits', () {
    const counts = UncommittedChangeCounts(
      added: 104,
      removed: 502,
      isClean: false,
    );
    expect(counts.caption, '+104 / -502');
  });

  test('caption is clean when the working tree matches HEAD', () {
    expect(UncommittedChangeCounts.clean.caption, 'clean');
  });

  test('caption is changed when dirty without line counts', () {
    const counts = UncommittedChangeCounts(
      added: 0,
      removed: 0,
      isClean: false,
    );
    expect(counts.caption, 'changed');
  });

  test('unified diff parser buckets insertions and deletions by file', () {
    const diff = '''
diff --git a/lib/a.dart b/lib/a.dart
index 1111111..2222222 100644
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,2 +1,3 @@
 class A {}
+class B {}
 class C {}
diff --git a/lib/gone.dart b/lib/gone.dart
deleted file mode 100644
--- a/lib/gone.dart
+++ /dev/null
@@ -1 +0,0 @@
-class Gone {}
''';
    final files = UncommittedPatch.fromGitDiff(diff);
    expect(files, hasLength(2));
    expect(files.first.path, 'lib/a.dart');
    expect(files.first.added, 1);
    expect(files.first.removed, 0);
    expect(files.last.path, 'lib/gone.dart');
    expect(files.last.removed, 1);
  });

  test('push output drops object-accounting noise', () {
    const stdout = '''
Enumerating objects: 12, done.
Counting objects: 100% (12/12), done.
Writing objects: 100% (6/6), 1.20 KiB | 1.20 MiB/s, done.
remote: Resolving deltas: 100% (2/2), completed with 2 local objects.
To github.com:ethan/ethan_workbench.git
   abc1234..def5678  main -> main
''';
    expect(GitUserFacingOutput.pushLines(stdout), [
      'To github.com:ethan/ethan_workbench.git',
      'abc1234..def5678  main -> main',
    ]);
  });

  test('failure message drops hint lines', () {
    const stderr = '''
error: failed to push some refs
hint: Updates were rejected because the remote contains work
hint: that you do not have locally.
''';
    expect(
      GitUserFacingOutput.failureMessage(stderr),
      'error: failed to push some refs',
    );
  });
}
