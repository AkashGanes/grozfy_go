import 'package:flutter/material.dart';

/// Bottom sheet confirming a driver-initiated order/stop status transition.
///
/// Shared by the active-order status flow (`OrderStatusScreen`) and the
/// multi-stop trip screen so both present the same confirm-before-transition
/// UX for the pickup → delivered/failed status flow.
class StatusConfirmSheet extends StatelessWidget {
  const StatusConfirmSheet({
    super.key,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.icon,
    required this.color,
  });

  final String title;
  final String body;
  final String actionLabel;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 28),
          // Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 38),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontSize: 14,
              color: scheme.onSurface.withValues(alpha: 0.55),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Not Yet',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows [StatusConfirmSheet] as a modal bottom sheet and returns whether the
/// driver confirmed the transition.
Future<bool?> showStatusConfirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String actionLabel,
  required IconData icon,
  required Color color,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatusConfirmSheet(
      title: title,
      body: body,
      actionLabel: actionLabel,
      icon: icon,
      color: color,
    ),
  );
}
