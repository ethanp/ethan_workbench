import 'package:ethan_utils/ethan_utils.dart';

/// Insertions and deletions in the working tree versus HEAD, plus untracked text.
class const UncommittedChangeCounts({
  required final int added,
  required final int removed,
  required final bool isClean,
}) {
  static const clean = UncommittedChangeCounts(
    added: 0,
    removed: 0,
    isClean: true,
  );

  bool get hasLineEdits => added > 0 || removed > 0;

  /// Row caption: `+104 / -502`, `changed`, or `clean`.
  String get caption {
    if (isClean) return 'clean';
    if (!hasLineEdits) return 'changed';
    return '+${added.asCompactCount} / -${removed.asCompactCount}';
  }
}
