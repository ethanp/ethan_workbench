import 'dart:typed_data';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import 'uncommitted_file_diff.dart';

class const CommitDiffPane({
  required final List<UncommittedFileDiff> files,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const EEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Working tree is clean',
        message: 'No local uncommitted changes.',
      );
    }
    final expandAll = files.length <= 6;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        ELayout.spaceLg,
        ELayout.spaceSm,
        ELayout.spaceLg,
        ELayout.spaceMd,
      ),
      itemCount: files.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: ELayout.spaceSm),
      itemBuilder: (context, index) => _FileDiffCard(
        file: files[index],
        initiallyExpanded: expandAll,
      ),
    );
  }
}

class const _FileDiffCard({
  required final UncommittedFileDiff file,
  required final bool initiallyExpanded,
}) extends StatefulWidget {
  @override
  State<_FileDiffCard> createState() => _FileDiffCardState();
}

class _FileDiffCardState() extends State<_FileDiffCard> {
  late var _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return ESurface(
      kind: ESurfaceKind.inset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fileHeader(),
          if (_expanded) _fileBody(),
        ],
      ),
    );
  }

  Widget _fileHeader() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ELayout.spaceMd,
            vertical: ELayout.spaceSm + 2,
          ),
          child: Row(
            children: [
              Icon(
                _expanded
                    ? Icons.expand_more_rounded
                    : Icons.chevron_right_rounded,
                size: 18,
                color: EColors.textMuted,
              ),
              const SizedBox(width: ELayout.spaceXs),
              Expanded(
                child: Text(
                  widget.file.path,
                  style: EText.monoEmphasis.copyWith(
                    color: EColors.textPrimary,
                    fontSize: ELayout.typeSize(13),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: ELayout.spaceSm),
              _statCaption(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCaption() {
    final file = widget.file;
    if (!file.isBinary && file.hasLineEdits) {
      return Text.rich(
        TextSpan(
          style: EText.caption.copyWith(fontSize: ELayout.typeSize(12)),
          children: [
            TextSpan(
              text: '+${file.added}',
              style: TextStyle(color: DiffLineKind.insertion.foreground),
            ),
            const TextSpan(text: ' / '),
            TextSpan(
              text: '-${file.removed}',
              style: TextStyle(color: DiffLineKind.deletion.foreground),
            ),
          ],
        ),
      );
    }
    return Text(file.statCaption, style: EText.caption);
  }

  Widget _fileBody() {
    final image = widget.file.image;
    if (image != null) return _imageDiff(image);
    if (widget.file.isBinary) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          ELayout.spaceLg,
          0,
          ELayout.spaceMd,
          ELayout.spaceMd,
        ),
        child: Text('Binary file', style: EText.caption),
      );
    }
    if (widget.file.lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          ELayout.spaceLg,
          0,
          ELayout.spaceMd,
          ELayout.spaceMd,
        ),
        child: Text('No textual diff', style: EText.caption),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ELayout.spaceMd,
        0,
        ELayout.spaceMd,
        ELayout.spaceMd,
      ),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in widget.file.lines) _diffLine(line),
          ],
        ),
      ),
    );
  }

  Widget _imageDiff(UncommittedImagePreview image) {
    final before = image.before;
    final after = image.after;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ELayout.spaceLg,
        0,
        ELayout.spaceMd,
        ELayout.spaceMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (before != null) _imageSide(after != null ? 'before' : null, before),
          if (before != null && after != null)
            const SizedBox(height: ELayout.spaceSm),
          if (after != null) _imageSide(before != null ? 'after' : null, after),
        ],
      ),
    );
  }

  Widget _imageSide(String? caption, Uint8List bytes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (caption != null) ...[
          Text(caption, style: EText.caption),
          const SizedBox(height: ELayout.spaceXs),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: EColors.border),
            borderRadius: ELayout.borderRadiusSm,
            color: EColors.surface,
          ),
          child: ClipRRect(
            borderRadius: ELayout.borderRadiusSm,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Image.memory(
                  bytes,
                  width: constraints.maxWidth,
                  fit: BoxFit.contain,
                  alignment: Alignment.topLeft,
                  errorBuilder: (context, error, stackTrace) {
                    return Padding(
                      padding: const EdgeInsets.all(ELayout.spaceSm),
                      child: Text(
                        'Could not decode image',
                        style: EText.caption,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _diffLine(UncommittedDiffLine line) {
    return Text(
      _prefixed(line),
      style: EText.mono.copyWith(
        color: line.kind.foreground,
        fontSize: ELayout.typeSize(12),
        height: 1.4,
      ),
    );
  }

  String _prefixed(UncommittedDiffLine line) {
    return switch (line.kind) {
      DiffLineKind.insertion => '+${line.text}',
      DiffLineKind.deletion => '-${line.text}',
      DiffLineKind.hunkHeader => line.text,
      DiffLineKind.context => ' ${line.text}',
    };
  }
}
