import 'package:flutter/material.dart';

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

  Color _bg() {
    switch (tone) {
      case StatusPillTone.success:
        return const Color(0xFF1AB36A).withValues(alpha: 0.12);
      case StatusPillTone.warning:
        return const Color(0xFFF6A623).withValues(alpha: 0.16);
      case StatusPillTone.info:
        return const Color(0xFF2D6CDF).withValues(alpha: 0.12);
      case StatusPillTone.danger:
        return const Color(0xFFE8384F).withValues(alpha: 0.12);
      case StatusPillTone.neutral:
        return const Color(0xFF6B7280).withValues(alpha: 0.12);
    }
  }

  Color _fg() {
    switch (tone) {
      case StatusPillTone.success:
        return const Color(0xFF118A52);
      case StatusPillTone.warning:
        return const Color(0xFFB87707);
      case StatusPillTone.info:
        return const Color(0xFF1F4FB6);
      case StatusPillTone.danger:
        return const Color(0xFFB7283A);
      case StatusPillTone.neutral:
        return const Color(0xFF4B5563);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = _fg();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: _bg(),
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
