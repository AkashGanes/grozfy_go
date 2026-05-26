import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Forced acknowledgement sheet shown the moment a Recall Pending is detected.
/// Used by the trip details screen, dashboard active-order section, and the
/// order-progress screen. [isDismissible: false] and [enableDrag: false] are
/// set by each call-site — this widget only builds the content.
class RecallInterstitialSheet extends StatelessWidget {
  const RecallInterstitialSheet({
    super.key,
    this.recallCount = 1,
    this.customerName,
    this.storeName,
  });

  final int recallCount;
  final String? customerName;
  final String? storeName;

  static const Color _orange = Color(0xFFE65100);

  @override
  Widget build(BuildContext context) {
    final title = recallCount == 1
        ? 'Order Recalled'
        : '$recallCount Orders Recalled';

    final String subtitle;
    if (customerName != null && customerName!.isNotEmpty) {
      subtitle =
          '$customerName cancelled their order.\nPlease return the items to the store.';
    } else if (recallCount == 1) {
      subtitle =
          'A customer cancelled their order while you were en route.\nPlease return the items to the store.';
    } else {
      subtitle =
          '$recallCount customers have cancelled their orders.\nPlease return their items to the store.';
    }

    final storeLabel =
        (storeName != null && storeName!.isNotEmpty) ? storeName! : 'the store';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, 24 + MediaQuery.of(context).viewPadding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle (visual only — sheet is non-dismissible)
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 28),

          // Pulsing warning icon
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              shape: BoxShape.circle,
              border:
                  Border.all(color: _orange.withValues(alpha: 0.3), width: 2),
            ),
            child: const Icon(Icons.u_turn_left_rounded,
                color: _orange, size: 36),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.08, 1.08),
                duration: 900.ms,
                curve: Curves.easeInOut,
              ),

          const SizedBox(height: 20),

          Text(
            title,
            style: const TextStyle(
              color: _orange,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          _step(
            Icons.u_turn_left_rounded,
            _orange,
            'Turn around and head back to $storeLabel',
          ),
          const SizedBox(height: 10),
          _step(
            Icons.store_rounded,
            const Color(0xFF1C4E80),
            'Hand items to the store dock staff',
          ),
          const SizedBox(height: 10),
          _step(
            Icons.check_circle_outline_rounded,
            const Color(0xFF2E7D32),
            'Tap "Confirm Recall at Store" to complete the return',
          ),

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.u_turn_left_rounded, size: 20),
              label: const Text(
                'Got it — Head to Store',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(IconData icon, Color color, String text) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF0E1B2B),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
