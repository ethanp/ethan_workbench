import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

enum GitCommitNoticeTone({required final Color foreground}) {
  info(foreground: EColors.textSecondary),
  success(foreground: EColors.success),
  danger(foreground: EColors.danger);
}

class const GitCommitNotice({
  required final String text,
  required final GitCommitNoticeTone tone,
}) {
  factory info(String text) =>
      GitCommitNotice(text: text, tone: GitCommitNoticeTone.info);

  factory success(String text) =>
      GitCommitNotice(text: text, tone: GitCommitNoticeTone.success);

  factory danger(String text) =>
      GitCommitNotice(text: text, tone: GitCommitNoticeTone.danger);
}
