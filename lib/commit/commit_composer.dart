import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import 'git_commit_notice.dart';

class const CommitComposer({
  required final TextEditingController messageController,
  required final List<GitCommitNotice> notices,
  required final String actionLabel,
  required final bool actionEnabled,
  required final bool messageEnabled,
  required final bool running,
  required final VoidCallback? onSubmit,
  required final ValueChanged<String> onMessageChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ESurface(
      kind: ESurfaceKind.panel,
      padding: const EdgeInsets.all(ELayout.spaceMd),
      child: _composerColumn(),
    );
  }

  Widget _composerColumn() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Widget draft = _draftAndNotices();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (constraints.hasBoundedHeight)
              Flexible(
                child: SingleChildScrollView(primary: false, child: draft),
              )
            else
              draft,
            const SizedBox(height: ELayout.spaceMd),
            _submitButton(),
          ],
        );
      },
    );
  }

  Widget _draftAndNotices() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notices.isNotEmpty) ...[
          _noticeLines(),
          const SizedBox(height: ELayout.spaceMd),
        ],
        _messageField(),
      ],
    );
  }

  Widget _messageField() {
    return TextField(
      controller: messageController,
      enabled: messageEnabled,
      onChanged: onMessageChanged,
      minLines: messageEnabled ? 3 : 1,
      maxLines: 8,
      textCapitalization: TextCapitalization.sentences,
      style: EText.body.medium,
      decoration: EInput.filled(
        hintText: 'Commit message',
        fillColor: EColors.surfaceInset,
      ),
    );
  }

  Widget _submitButton() {
    return FilledButton(
      onPressed: actionEnabled ? onSubmit : null,
      child: running ? _runningLabel() : Text(actionLabel),
    );
  }

  Widget _runningLabel() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: ELayout.spaceSm),
        Text(actionLabel),
      ],
    );
  }

  Widget _noticeLines() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < notices.length; index++) ...[
          if (index > 0) const SizedBox(height: ELayout.spaceXs),
          SelectableText(
            notices[index].text,
            style: EText.body.small.copyWith(
              color: notices[index].tone.foreground,
            ),
          ),
        ],
      ],
    );
  }
}
