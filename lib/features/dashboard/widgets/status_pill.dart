import 'package:flutter/material.dart';

import '../../../core/theme/context_colors.dart';

enum StatusPillTone { success, warning, info, danger, neutral }

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = StatusPillTone.success,
    this.icon,
    this.dense = false,
  });

  final String label;
  final StatusPillTone tone;
  final IconData? icon;
  final bool dense;

  Color _bg(BuildContext context) {
    switch (tone) {
      case StatusPillTone.success:
        return context.successContainer;
      case StatusPillTone.warning:
        return context.warningContainer;
      case StatusPillTone.info:
        return context.infoContainer;
      case StatusPillTone.danger:
        return context.dangerContainer;
      case StatusPillTone.neutral:
        return context.fillMuted;
    }
  }

  Color _fg(BuildContext context) {
    switch (tone) {
      case StatusPillTone.success:
        return context.success;
      case StatusPillTone.warning:
        return context.warning;
      case StatusPillTone.info:
        return context.info;
      case StatusPillTone.danger:
        return context.danger;
      case StatusPillTone.neutral:
        return context.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = _fg(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: _bg(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Container(
              width: dense ? 5 : 6,
              height: dense ? 5 : 6,
              decoration: BoxDecoration(
                color: fg,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: dense ? 10 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
