import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/context_colors.dart';
import '../../../core/widgets/app_bottom_sheet.dart';

/// Shows a bottom sheet where the driver selects how the COD customer paid.
/// The [amountToCollect] is displayed read-only as a reference.
/// Returns `({mode, upiRef})` on confirm, or null if the driver dismisses.
Future<({String mode, String? upiRef})?> showCodCollectionSheet(
  BuildContext context, {
  required double amountToCollect,
}) {
  return showAppBottomSheet<({String mode, String? upiRef})>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _CodCollectionSheet(amountToCollect: amountToCollect),
  );
}

class _CodCollectionSheet extends StatefulWidget {
  const _CodCollectionSheet({required this.amountToCollect});
  final double amountToCollect;

  @override
  State<_CodCollectionSheet> createState() => _CodCollectionSheetState();
}

class _CodCollectionSheetState extends State<_CodCollectionSheet> {
  String _mode = 'Cash';
  final TextEditingController _upiRefController = TextEditingController();
  bool _upiRefError = false;

  @override
  void dispose() {
    _upiRefController.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_mode == 'UPI') {
      final ref = _upiRefController.text.trim();
      if (ref.isEmpty) {
        setState(() => _upiRefError = true);
        return;
      }
      Navigator.of(context).pop((mode: _mode, upiRef: ref));
    } else {
      Navigator.of(context).pop((mode: _mode, upiRef: null));
    }
  }

  Color get _confirmColor => _mode == 'Not Collected'
      ? const Color(0xFFE65100)
      : const Color(0xFF2E7D32);

  String get _confirmLabel {
    if (_mode == 'UPI') return 'Confirm — UPI Paid';
    if (_mode == 'Not Collected') return 'Confirm — Not Collected';
    return 'Confirm — Cash Collected';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amountText =
        '₹${widget.amountToCollect.toStringAsFixed(widget.amountToCollect.truncateToDouble() == widget.amountToCollect ? 0 : 2)}';

    return AppBottomSheet(
      scrollable: true,
      title: 'COD Payment',
      subtitle: 'Collect cash or confirm UPI before marking delivered',
      leadingIcon: Icons.payments_rounded,
      leadingIconColor: const Color(0xFF2E7D32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // ── Amount banner ─────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.currency_rupee_rounded,
                    color: Color(0xFF2E7D32),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Amount to Collect',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      amountText,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2E7D32),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // ── Payment method label ──────────────────────────────────────────
          Text(
            'How did the customer pay?',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 10),

          // ── Cash / UPI toggle ─────────────────────────────────────────────
          Row(
            children: [
              Expanded(child: _ModeOption(
                label: 'Cash',
                icon: Icons.money_rounded,
                selected: _mode == 'Cash',
                onTap: () => setState(() {
                  _mode = 'Cash';
                  _upiRefError = false;
                }),
              )),
              const SizedBox(width: 10),
              Expanded(child: _ModeOption(
                label: 'UPI',
                icon: Icons.qr_code_rounded,
                selected: _mode == 'UPI',
                onTap: () => setState(() => _mode = 'UPI'),
              )),
            ],
          ),

          // ── UPI reference field ───────────────────────────────────────────
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
                          controller: _upiRefController,
                          textInputAction: TextInputAction.done,
                          textCapitalization: TextCapitalization.characters,
                          onChanged: (_) {
                            if (_upiRefError) {
                              setState(() => _upiRefError = false);
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'e.g. AXY88392',
                            hintStyle: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.35),
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(
                              Icons.tag_rounded,
                              size: 18,
                            ),
                            errorText: _upiRefError
                                ? 'Please enter the UPI reference'
                                : null,
                            filled: true,
                            fillColor: scheme.onSurface.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: scheme.onSurface.withValues(alpha: 0.12),
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
                              borderSide: const BorderSide(color: Colors.red),
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

          // ── Not Collected option ──────────────────────────────────────────
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => setState(() {
              _mode = _mode == 'Not Collected' ? 'Cash' : 'Not Collected';
              _upiRefError = false;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: _mode == 'Not Collected'
                    ? const Color(0xFFE65100).withValues(alpha: 0.08)
                    : scheme.onSurface.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _mode == 'Not Collected'
                      ? const Color(0xFFE65100).withValues(alpha: 0.5)
                      : scheme.onSurface.withValues(alpha: 0.1),
                  width: _mode == 'Not Collected' ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.money_off_rounded,
                    size: 22,
                    color: _mode == 'Not Collected'
                        ? const Color(0xFFE65100)
                        : scheme.onSurface.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cash not collected',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _mode == 'Not Collected'
                                ? const Color(0xFFE65100)
                                : scheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          'Customer did not pay — flag for follow-up',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _mode == 'Not Collected'
                          ? const Color(0xFFE65100)
                          : Colors.transparent,
                      border: Border.all(
                        color: _mode == 'Not Collected'
                            ? const Color(0xFFE65100)
                            : scheme.onSurface.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: _mode == 'Not Collected'
                        ? const Icon(Icons.check, size: 13, color: Colors.white)
                        : null,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Confirm button ────────────────────────────────────────────────
          AppSheetPrimaryButton(
            label: _confirmLabel,
            icon: Icons.check_circle_rounded,
            color: _confirmColor,
            onPressed: _confirm,
          ),
          const SizedBox(height: 8),
          AppSheetSecondaryButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(null),
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
              color: selected ? activeColor : scheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? activeColor : scheme.onSurface.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            if (selected) ...[
              const SizedBox(height: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
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
