import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/context_colors.dart';

/// Forced acknowledgement sheet shown the moment a Recall Pending is detected.
/// Used by the trip details screen, dashboard active-order section, and the
/// order-progress screen. [isDismissible: false] and [enableDrag: false] are
/// set by each call-site — this widget only builds the content.
///
/// 2026 redesign: clean, minimal card inspired by top delivery apps (Swiggy,
/// Zomato, Dunzo). Dark-mode adaptive via the caller's [Theme].
class RecallInterstitialSheet extends StatelessWidget {
  const RecallInterstitialSheet({
    super.key,
    this.recallCount = 1,
    this.customerName,
    this.storeName,
    this.orderId,
    this.itemCount,
  });

  final int recallCount;
  final String? customerName;
  final String? storeName;
  final String? orderId;
  final int? itemCount;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;

    // ── Colors ─────────────────────────────────────────────────────────────────
    final Color surface = context.cardColor;
    final Color textPrimary = context.textPrimary;
    final Color textSecondary = context.textSecondary;
    final Color divider = context.borderSubtle;
    final Color subtleFill = context.surfaceContainer;
    final Color cancelRed = context.danger;
    final Color cancelRedBg = context.dangerContainer;

    // Solid CTA button fill (white label) — kept brightness-branched because
    // the success token is a foreground color, too bright for a filled button.
    final Color ctaGreenBg = isDark
        ? const Color(0xFF14532D)
        : const Color(0xFF16A34A);
    final Color infoBg = context.infoContainer;
    final Color infoIcon = context.info;

    // ── Labels ────────────────────────────────────────────────────────────────
    final title = recallCount == 1
        ? 'Order Cancelled by Customer'
        : '$recallCount Orders Cancelled';

    final subtitle = customerName != null && customerName!.isNotEmpty
        ? 'The customer has cancelled this order while you were\nout for delivery.'
        : recallCount == 1
        ? 'The customer has cancelled this order while you were\nout for delivery.'
        : '$recallCount customers cancelled their orders while\nyou were out for delivery.';

    final storeLabel = (storeName != null && storeName!.isNotEmpty)
        ? storeName!
        : 'the store';

    final bool hasOrderDetails =
        (orderId != null && orderId!.isNotEmpty) || (itemCount ?? 0) > 0;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
            blurRadius: 30,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        24 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ───────────────────────────────────────────────────
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: divider,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 28),

          // ── Animated icon ─────────────────────────────────────────────────
          Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: cancelRedBg,
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.inventory_2_rounded, color: cancelRed, size: 30),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: surface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.cancel_rounded,
                          color: cancelRed,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(
                begin: 1,
                end: 1.06,
                duration: 1400.ms,
                curve: Curves.easeInOut,
              ),

          const SizedBox(height: 20),

          // ── Title ─────────────────────────────────────────────────────────
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              height: 1.25,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),

          // ── Subtitle ──────────────────────────────────────────────────────
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textSecondary,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),

          // ── Order Details section ─────────────────────────────────────────
          if (hasOrderDetails) ...[
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: subtleFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: divider, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section header.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 14,
                          decoration: BoxDecoration(
                            color: textPrimary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Order Details',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: divider),

                  // Detail rows.
                  if (orderId != null && orderId!.isNotEmpty)
                    _detailRow(
                      'Order ID',
                      '#$orderId',
                      textSecondary,
                      textPrimary,
                      divider,
                      isLast: (itemCount ?? 0) <= 0,
                    ),
                  if ((itemCount ?? 0) > 0)
                    _detailRow(
                      'Items',
                      '$itemCount item${itemCount == 1 ? '' : 's'}',
                      textSecondary,
                      textPrimary,
                      divider,
                      isLast: true,
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ── Info tip ──────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: infoBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: infoIcon.withValues(alpha: 0.15)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: infoIcon,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Please return the items to $storeLabel.\nConfirm the return once handed over.',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── CTA button ────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ctaGreenBg,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Got it',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A single label–value row inside the "Order Details" card.
  Widget _detailRow(
    String label,
    String value,
    Color labelColor,
    Color valueColor,
    Color dividerColor, {
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
      ],
    );
  }
}
