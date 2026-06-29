import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/context_colors.dart';
import '../../../core/widgets/app_bottom_sheet.dart';

typedef DeliveryOutcomeResult = ({
  String outcome, // 'delivered' | 'failed'
  String? codMode,
  String? codRef,
});

/// Shows a single bottom sheet that handles both COD collection AND the
/// delivery outcome decision.
///
/// For COD orders: the driver fills in payment details then taps
/// "Confirm Delivery" or "Mark as Failed".
/// For non-COD orders: just the two outcome buttons.
///
/// Returns:
///  • `(outcome: 'delivered', codMode: ..., codRef: ...)` — driver confirmed
///  • `(outcome: 'failed',    codMode: null, codRef: null)` — driver chose failed
///  • `null` — dismissed without choosing
Future<DeliveryOutcomeResult?> showDeliveryOutcomeSheet(
  BuildContext context, {
  required bool isCod,
  required double codAmount,
}) {
  return showAppBottomSheet<DeliveryOutcomeResult>(
    context: context,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => _DeliveryOutcomeSheet(isCod: isCod, codAmount: codAmount),
  );
}

class _DeliveryOutcomeSheet extends StatefulWidget {
  const _DeliveryOutcomeSheet({
    required this.isCod,
    required this.codAmount,
  });
  final bool isCod;
  final double codAmount;

  @override
  State<_DeliveryOutcomeSheet> createState() => _DeliveryOutcomeSheetState();
}

class _DeliveryOutcomeSheetState extends State<_DeliveryOutcomeSheet> {
  String _mode = 'Cash';
  final TextEditingController _upiRef = TextEditingController();
  bool _upiRefError = false;

  @override
  void dispose() {
    _upiRef.dispose();
    super.dispose();
  }

  void _confirmDelivery() {
    if (widget.isCod && _mode == 'UPI') {
      final ref = _upiRef.text.trim();
      if (ref.isEmpty) {
        setState(() => _upiRefError = true);
        return;
      }
      Navigator.of(context).pop(
        (outcome: 'delivered', codMode: _mode, codRef: ref),
      );
    } else {
      Navigator.of(context).pop(
        (outcome: 'delivered', codMode: widget.isCod ? _mode : null, codRef: null),
      );
    }
  }

  void _markFailed() {
    Navigator.of(context).pop(
      (outcome: 'failed', codMode: null, codRef: null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppBottomSheet(
      scrollable: true,
      title: 'Complete Delivery',
      subtitle: widget.isCod
          ? 'Collect COD payment, then confirm or report issue'
          : 'Confirm delivery or report a problem',
      leadingIcon: Icons.local_shipping_rounded,
      leadingIconColor: const Color(0xFF2E7D32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isCod) ...[
            const SizedBox(height: 16),

            // ── COD amount banner ─────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFE6A817).withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6A817).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.currency_rupee_rounded,
                      color: Color(0xFF8A5700),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COD Amount to Collect',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.codAmount > 0
                            ? '₹${widget.codAmount.toStringAsFixed(widget.codAmount.truncateToDouble() == widget.codAmount ? 0 : 2)}'
                            : 'Collect from customer',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF8A5700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ── Payment method question ────────────────────────────────────
            Text(
              'How did the customer pay?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 10),

            // ── Cash / UPI toggle ─────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _ModeOption(
                    label: 'Cash',
                    icon: Icons.money_rounded,
                    selected: _mode == 'Cash',
                    onTap: () => setState(() {
                      _mode = 'Cash';
                      _upiRefError = false;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ModeOption(
                    label: 'UPI',
                    icon: Icons.qr_code_rounded,
                    selected: _mode == 'UPI',
                    onTap: () => setState(() => _mode = 'UPI'),
                  ),
                ),
              ],
            ),

            // ── UPI reference ─────────────────────────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: _mode == 'UPI'
                  ? Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'UPI Transaction Reference',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _upiRef,
                            textInputAction: TextInputAction.done,
                            textCapitalization: TextCapitalization.characters,
                            onChanged: (_) {
                              if (_upiRefError) {
                                setState(() => _upiRefError = false);
                              }
                            },
                            decoration: InputDecoration(
                              hintText: 'e.g. AXY88392',
                              prefixIcon:
                                  const Icon(Icons.tag_rounded, size: 18),
                              errorText: _upiRefError
                                  ? 'Please enter the UPI reference'
                                  : null,
                              filled: true,
                              fillColor:
                                  scheme.onSurface.withValues(alpha: 0.05),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.12),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: AppTheme.oceanBlue,
                                  width: 1.5,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Colors.red),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Colors.red,
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            Divider(
              height: 28,
              color: scheme.onSurface.withValues(alpha: 0.08),
            ),
          ] else ...[
            const SizedBox(height: 16),
          ],

          // ── Confirm Delivery button ────────────────────────────────────
          AppSheetPrimaryButton(
            label: widget.isCod
                ? (_mode == 'Cash'
                    ? 'Confirm Delivery — Cash Collected'
                    : 'Confirm Delivery — UPI Paid')
                : 'Confirm Delivery',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF2E7D32),
            onPressed: _confirmDelivery,
          ),

          const SizedBox(height: 10),

          // ── Mark as Failed button ─────────────────────────────────────
          SizedBox(
            height: kSheetButtonHeight,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _markFailed,
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Mark as Failed'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFC62828),
                side: const BorderSide(
                  color: Color(0xFFC62828),
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kSheetButtonRadius),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const activeColor = AppTheme.oceanBlue;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.1)
              : scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? activeColor.withValues(alpha: 0.5)
                : scheme.onSurface.withValues(alpha: 0.1),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 28,
              color: selected
                  ? activeColor
                  : scheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? activeColor
                    : scheme.onSurface.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            if (selected) ...[
              const SizedBox(height: 4),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: activeColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
