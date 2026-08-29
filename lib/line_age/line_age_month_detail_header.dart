import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

import 'line_age_analyzer.dart';
import 'line_age_directory_groups.dart';
import 'line_age_month_detail_panel.dart';

/// App-bar trailing slot: empty hint or selected-month summary + file-list popover.
class LineAgeMonthDetailHeaderAction extends StatefulWidget {
  const LineAgeMonthDetailHeaderAction({
    required this.report,
    required this.legend,
    required this.month,
    required this.focusedFile,
    required this.emphasizedDirectory,
    required this.onFocusFile,
    required this.onHoverDirectory,
    required this.onDismissed,
  });

  final LineAgeReport report;
  final LineAgeDirectoryLegend legend;
  final LineAgeMonth? month;
  final String? focusedFile;
  final String? emphasizedDirectory;
  final ValueChanged<String?> onFocusFile;
  final ValueChanged<String?> onHoverDirectory;
  final VoidCallback onDismissed;

  static const width = 200.0;

  @override
  State<LineAgeMonthDetailHeaderAction> createState() =>
      _LineAgeMonthDetailHeaderActionState();
}

class _LineAgeMonthDetailHeaderActionState
    extends State<LineAgeMonthDetailHeaderAction> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _syncPortalAfterFrame();
  }

  @override
  void didUpdateWidget(covariant LineAgeMonthDetailHeaderAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPortalAfterFrame();
  }

  void _syncPortalAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final shouldShow = widget.month != null;
      if (shouldShow && !_portal.isShowing) {
        _portal.show();
      } else if (!shouldShow && _portal.isShowing) {
        _portal.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: LineAgeMonthDetailHeaderAction.width,
      ),
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _fileListOverlay,
        child: CompositedTransformTarget(
          link: _layerLink,
          child: widget.month == null
              ? _titleCaption(
                  title: 'File breakdown',
                  caption: 'Click a bar to show',
                )
              : _titleCaption(
                  title: widget.month!.month,
                  caption:
                      '${widget.month!.totalLines.asCompactCount} lines · '
                      '${widget.month!.segments.length} files',
                ),
        ),
      ),
    );
  }

  Widget _fileListOverlay(BuildContext context) {
    final month = widget.month;
    if (month == null) return const SizedBox.shrink();
    final maxHeight = (MediaQuery.sizeOf(context).height * 0.55).clamp(240.0, 560.0);
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismissed,
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 16),
            child: Material(
              elevation: 8,
              color: Colors.transparent,
              shadowColor: Colors.black.withValues(alpha: 0.45),
              borderRadius: ELayout.borderRadiusMd,
              child: LineAgeMonthFileList(
                report: widget.report,
                legend: widget.legend,
                month: month,
                focusedFile: widget.focusedFile,
                emphasizedDirectory: widget.emphasizedDirectory,
                onFocusFile: widget.onFocusFile,
                onHoverDirectory: widget.onHoverDirectory,
                maxHeight: maxHeight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _titleCaption({required String title, required String caption}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: EText.label.copyWith(color: EColors.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: EText.caption.copyWith(color: EColors.textMuted),
        ),
      ],
    );
  }
}
