import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import '../commit/uncommitted_change_counts.dart';
import '../commit/uncommitted_file_diff.dart';
import '../ui/workbench_action_accents.dart';
import 'project_app_icon_tile.dart';
import 'workbench_project.dart';

class const WorkbenchRowIdentity({required final WorkbenchProject project})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProjectAppIconTile(
          iconPngBytes: project.iconPngBytes,
          size: ELayout.listRowIcon,
        ),
        const SizedBox(height: ELayout.spaceXs),
        Text(
          project.name,
          style: EText.caption.copyWith(
            color: EColors.textPrimary,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class const WorkbenchIconCaptionAction({
  required final Color accent,
  required final IconData icon,
  required final String tooltip,
  required final Widget caption,
  required final VoidCallback? onActivated,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ESurface(
        kind: ESurfaceKind.tinted,
        accent: accent,
        onActivated: onActivated,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: SizedBox(
          height: 44,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(height: 2),
              FittedBox(fit: BoxFit.scaleDown, child: caption),
            ],
          ),
        ),
      ),
    );
  }
}

class const WorkbenchRowLineAgeAction({
  required final String lineAgeSubtitle,
  required final VoidCallback onLineAge,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return WorkbenchIconCaptionAction(
      accent: WorkbenchActionAccents.lineAge,
      icon: Icons.bar_chart_rounded,
      tooltip: 'Line age · $lineAgeSubtitle',
      caption: Text(
        lineAgeSubtitle,
        style: EText.caption.copyWith(
          color: WorkbenchActionAccents.lineAge.withValues(alpha: 0.62),
          fontSize: ELayout.typeSize(12),
          height: 1.15,
        ),
        maxLines: 1,
      ),
      onActivated: onLineAge,
    );
  }
}

class const WorkbenchRowCommitAction({
  required final UncommittedChangeCounts? uncommittedChanges,
  required final VoidCallback? onCommit,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final counts = uncommittedChanges;
    final caption = counts?.caption ?? '…';
    final canCommit = counts != null && !counts.isClean;
    return WorkbenchIconCaptionAction(
      accent: canCommit
          ? WorkbenchActionAccents.commit
          : WorkbenchActionAccents.commit.withValues(alpha: 0.38),
      icon: Icons.commit_rounded,
      tooltip: counts == null
          ? 'Counting uncommitted changes'
          : canCommit
          ? 'Commit · $caption'
          : 'Working tree is clean',
      caption: WorkbenchRowCommitCaption(counts: counts),
      onActivated: canCommit ? onCommit : null,
    );
  }
}

class const WorkbenchRowCommitCaption({
  required final UncommittedChangeCounts? counts,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = EText.caption.copyWith(
      fontSize: ELayout.typeSize(12),
      height: 1.15,
    );
    final changeCounts = counts;
    if (changeCounts == null) {
      return Text(
        '…',
        style: style.copyWith(
          color: WorkbenchActionAccents.commit.withValues(alpha: 0.62),
        ),
        maxLines: 1,
      );
    }
    if (changeCounts.isClean || !changeCounts.hasLineEdits) {
      return Text(
        changeCounts.caption,
        style: style.copyWith(
          color: WorkbenchActionAccents.commit.withValues(alpha: 0.62),
        ),
        maxLines: 1,
      );
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(
            text: '+${changeCounts.added.asCompactCount}',
            style: TextStyle(color: DiffLineKind.insertion.foreground),
          ),
          TextSpan(
            text: ' / ',
            style: TextStyle(
              color: WorkbenchActionAccents.commit.withValues(alpha: 0.62),
            ),
          ),
          TextSpan(
            text: '-${changeCounts.removed.asCompactCount}',
            style: TextStyle(color: DiffLineKind.deletion.foreground),
          ),
        ],
      ),
      maxLines: 1,
    );
  }
}
