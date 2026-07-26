import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

class LogConsole extends StatelessWidget {
  const LogConsole({
    super.key,
    required this.log,
    this.controller,
    this.maxHeight,
    this.emptyMessage = '(no log yet)',
  });

  final String log;
  final ScrollController? controller;
  final double? maxHeight;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final console = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceInset,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Scrollbar(
        controller: controller,
        child: SingleChildScrollView(
          controller: controller,
          reverse: controller == null,
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            log.isEmpty ? emptyMessage : log,
            style: AppText.mono,
          ),
        ),
      ),
    );

    if (maxHeight == null) return console;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight!),
      child: console,
    );
  }
}
