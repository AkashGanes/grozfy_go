import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/context_colors.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../model/cod_handover.dart';

/// Shows the end-of-trip COD reconciliation sheet.
/// Driver enters the actual cash in hand; expected amount is read-only.
/// Returns `({actualAmount, notes})` on submit, or null if dismissed.
Future<({double actualAmount, String? notes})?> showCodHandoverSheet(
  BuildContext context, {
  required CodHandover codHandover,
}) {
  return showAppBottomSheet<({double actualAmount, String? notes})>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _CodHandoverSheet(codHandover: codHandover),
  );
}

class _CodHandoverSheet extends StatefulWidget {
  const _CodHandoverSheet({required this.codHandover});
  final CodHandover codHandover;

  @override
  State<_CodHandoverSheet> createState() => _CodHandoverSheetState();
}

class _CodHandoverSheetState extends State<_CodHandoverSheet> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  double? _actualAmount;
  bool _amountError = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _expected => widget.codHandover.codCashExpected;

  double? get _difference {
    if (_actualAmount == null) return null;
    return _actualAmount! - _expected;
  }

  void _onAmountChanged(String val) {
    final parsed = double.tryParse(val.trim());
    setState(() {
      _actualAmount = parsed;
      _amountError = false;
    });
  }

  void _submit() {
    if (_actualAmount == null) {
      setState(() => _amountError = true);
      return;
    }
    Navigator.of(context).pop((
      actualAmount: _actualAmount!,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final diff = _difference;
    final bool hasDiscrepancy = diff != null && diff.abs() > 0.01;
    final bool isShort = hasDiscrepancy && diff < 0;

    String fmt(double v) =>
        '₹${v.abs().toStringAsFixed(v.truncateToDouble() == v ? 0 : 2)}';

    return AppBottomSheet(
      scrollable: true,
      title: 'COD Handover',
      subtitle: 'Reconcile total cash before completing the trip',
      leadingIcon: Icons.account_balance_wallet_rounded,
      leadingIconColor: AppTheme.oceanBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // ── Expected total banner ─────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.oceanBlue.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.oceanBlue.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.oceanBlue.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: AppTheme.oceanBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Expected COD Total',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fmt(_expected),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.oceanBlue,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // ── Actual amount input ───────────────────────────────────────────
          Text(
            'Cash Actually in Hand',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            textInputAction: TextInputAction.next,
            onChanged: _onAmountChanged,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 14, right: 4),
                child: Text(
                  '₹',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              hintText: '0',
              hintStyle: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.3),
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              errorText: _amountError ? 'Please enter the cash amount' : null,
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
                borderSide: const BorderSide(color: Colors.red, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 16,
              ),
            ),
          ),

          // ── Difference indicator ──────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: diff != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _DifferenceRow(
                      diff: diff,
                      isShort: isShort,
                      fmtFn: fmt,
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: 18),

          // ── Notes field ───────────────────────────────────────────────────
          Text(
            'Notes (optional)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            maxLines: 2,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: hasDiscrepancy
                  ? 'Explain the difference...'
                  : 'Any additional notes...',
              hintStyle: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.35),
                fontSize: 13,
              ),
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Submit button ─────────────────────────────────────────────────
          AppSheetPrimaryButton(
            label: 'Submit Handover',
            icon: Icons.check_circle_rounded,
            color: AppTheme.oceanBlue,
            onPressed: _submit,
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

class _DifferenceRow extends StatelessWidget {
  const _DifferenceRow({
    required this.diff,
    required this.isShort,
    required this.fmtFn,
  });

  final double diff;
  final bool isShort;
  final String Function(double) fmtFn;

  @override
  Widget build(BuildContext context) {
    final bool isExact = diff.abs() < 0.01;
    final Color color = isExact
        ? const Color(0xFF2E7D32)
        : isShort
            ? Colors.red
            : const Color(0xFFE65100);
    final IconData icon = isExact
        ? Icons.check_circle_rounded
        : isShort
            ? Icons.arrow_downward_rounded
            : Icons.arrow_upward_rounded;
    final String label = isExact
        ? 'Exact match'
        : isShort
            ? 'Short by ${fmtFn(diff)}'
            : 'Excess by ${fmtFn(diff)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
