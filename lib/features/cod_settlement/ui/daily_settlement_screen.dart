import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_routes.dart';
import '../../../core/theme/context_colors.dart';
import '../../../core/widgets/app_shell.dart';
import '../model/cod_limit_status.dart';
import '../model/daily_driver_settlement.dart';
import '../providers/settlement_provider.dart';
import '../repository/cod_settlement_repository.dart';

class DailySettlementScreen extends ConsumerStatefulWidget {
  const DailySettlementScreen({super.key});

  @override
  ConsumerState<DailySettlementScreen> createState() =>
      _DailySettlementScreenState();
}

class _DailySettlementScreenState
    extends ConsumerState<DailySettlementScreen> {
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();

  String? _amountError;
  String? _referenceError;
  String? _submitError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() {
      if (_amountError != null) setState(() => _amountError = null);
      if (_submitError != null) setState(() => _submitError = null);
    });
    _referenceController.addListener(() {
      if (_referenceError != null) setState(() => _referenceError = null);
      if (_submitError != null) setState(() => _submitError = null);
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Status theming
  // ---------------------------------------------------------------------------

  static List<Color> _heroGradient(String? status) {
    switch (status) {
      case 'Fully Settled':
        return [const Color(0xFF16A34A), const Color(0xFF059669)];
      case 'Partially Settled':
        return [const Color(0xFF2563EB), const Color(0xFF1D4ED8)];
      case 'Discrepancy':
        return [const Color(0xFFD97706), const Color(0xFFB45309)];
      default:
        return [const Color(0xFF1C4E80), const Color(0xFF1565C0)];
    }
  }

  static Color _statusColor(String? status) {
    switch (status) {
      case 'Fully Settled':
        return const Color(0xFF16A34A);
      case 'Partially Settled':
        return const Color(0xFF2563EB);
      case 'Discrepancy':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF1C4E80);
    }
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  bool _validate() {
    String? amountErr;
    String? refErr;

    final rawAmount = _amountController.text.trim();
    if (rawAmount.isEmpty) {
      amountErr = 'Please enter the amount transferred';
    } else {
      final parsed = double.tryParse(rawAmount);
      if (parsed == null) {
        amountErr = 'Please enter a valid amount';
      } else if (parsed <= 0) {
        amountErr = 'Amount must be greater than zero';
      }
    }

    final rawRef = _referenceController.text.trim();
    if (rawRef.isEmpty) {
      refErr = 'Please enter the bank transfer reference';
    } else if (rawRef.length < 6) {
      refErr = 'Reference number is too short';
    }

    setState(() {
      _amountError = amountErr;
      _referenceError = refErr;
    });
    return amountErr == null && refErr == null;
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _onSubmitTapped(DailyDriverSettlement settlement) async {
    if (!_validate()) return;

    final amount = double.parse(_amountController.text.trim());
    final reference = _referenceController.text.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: ctx.scheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.send_rounded,
                color: ctx.scheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Confirm Transfer',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            _ConfirmRow(label: 'Amount', value: '₹${_fmtAmount(amount)}'),
            const SizedBox(height: 8),
            _ConfirmRow(label: 'Reference', value: reference),
            const SizedBox(height: 20),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ctx.scheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Confirm',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final result = await CodSettlementRepository().submitBankTransfer(
        settlementName: settlement.settlementName!,
        amountTransferred: amount,
        bankTransferReference: reference,
      );

      if (!mounted) return;

      if (result.success) {
        showInfoSnack(context, 'Transfer submitted successfully.');
        ref.invalidate(settlementProvider);
        // Settling frees cash-in-hand headroom, so the limit must refetch too.
        ref.invalidate(codLimitStatusProvider);
      } else {
        setState(() {
          _submitError = result.message.isNotEmpty
              ? result.message
              : 'Submission failed. Please try again.';
          _isSubmitting = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = e.toString().replaceFirst('Exception: ', '');
        _isSubmitting = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final settlementAsync = ref.watch(settlementProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: const Text(
          'My Settlement',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: settlementAsync.when(
        loading: _buildLoading,
        error: (err, _) => _buildError(err.toString()),
        data: (settlement) {
          if (settlement == null) return _buildEmpty();
          return _buildContent(settlement);
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Widget _buildLoading() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C4E80), Color(0xFF1565C0)],
          stops: [0.0, 0.45],
        ),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Error
  // ---------------------------------------------------------------------------

  Widget _buildError(String message) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: context.dangerContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.wifi_off_rounded,
                    size: 36,
                    color: context.danger,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Unable to load settlement',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Please check your connection and try again.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 160,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => ref.invalidate(settlementProvider),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      'Try Again',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.scheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty
  // ---------------------------------------------------------------------------

  Widget _buildEmpty() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: context.successContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 48,
                    color: context.success,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'All Clear Today!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'You have no COD orders to settle today.\nCome back after your first delivery.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Main content
  // ---------------------------------------------------------------------------

  Widget _buildContent(DailyDriverSettlement settlement) {
    final gradient = _heroGradient(settlement.status);
    final bool isPending = settlement.status == 'Pending';
    final bool isSubmitted = !isPending;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hero banner ───────────────────────────────────────────────────
          _HeroBanner(settlement: settlement, gradient: gradient),

          // ── Content area ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Breakdown chips (overlapping hero via negative margin)
                Transform.translate(
                  offset: const Offset(0, -24),
                  child: _BreakdownRow(settlement: settlement),
                ),

                const SizedBox(height: 4),

                // View Order Breakdown button
                _OrderBreakdownButton(settlement: settlement),

                // Cash-in-hand vs. limit. Hides itself (including its spacing)
                // when no COD limit is configured for this driver.
                const _CashLimitRow(),

                const SizedBox(height: 24),

                // Status banner (after submission)
                if (settlement.status == 'Fully Settled')
                  _StatusCard(
                    color: const Color(0xFF16A34A),
                    icon: Icons.check_circle_rounded,
                    title: 'Payment Complete',
                    subtitle:
                        '₹${_fmtAmount(settlement.amountTransferred ?? 0)} transferred successfully.',
                  ),
                if (settlement.status == 'Partially Settled')
                  _StatusCard(
                    color: const Color(0xFF2563EB),
                    icon: Icons.info_rounded,
                    title: 'Partial Payment',
                    subtitle:
                        '₹${_fmtAmount(settlement.carryForwardToTomorrow)} will carry forward to tomorrow.',
                  ),
                if (settlement.status == 'Discrepancy')
                  _StatusCard(
                    color: const Color(0xFFD97706),
                    icon: Icons.warning_rounded,
                    title: 'Settlement Flagged',
                    subtitle:
                        'Your supervisor will review and contact you shortly.',
                  ),

                // Transfer details
                if (isSubmitted) ...[
                  const SizedBox(height: 4),
                  _SubmittedDetailsCard(settlement: settlement),
                ],

                if (isPending) ...[
                  _TransferFormCard(
                    amountController: _amountController,
                    referenceController: _referenceController,
                    amountError: _amountError,
                    referenceError: _referenceError,
                    submitError: _submitError,
                    isSubmitting: _isSubmitting,
                    accentColor: _statusColor(settlement.status),
                    onSubmit: () => _onSubmitTapped(settlement),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero banner
// ---------------------------------------------------------------------------

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.settlement,
    required this.gradient,
  });

  final DailyDriverSettlement settlement;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top + kToolbarHeight;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, topPad + 12, 24, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Status pill
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    settlement.status ?? 'Unknown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Amount label
            Text(
              'Total You Owe',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.80),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),

            // Amount
            Text(
              '₹${_fmtAmount(settlement.totalOwed)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 52,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 14),

            // Date
            Text(
              _formatDate(settlement.settlementDate ?? ''),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.70),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(String raw) {
    if (raw.isEmpty) return '';
    try {
      final parts = raw.split('-');
      if (parts.length != 3) return raw;
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final day = int.tryParse(parts[2]) ?? 0;
      final month = int.tryParse(parts[1]) ?? 0;
      if (month < 1 || month > 12) return raw;
      return '$day ${months[month]} ${parts[0]}';
    } catch (_) {
      return raw;
    }
  }
}

// ---------------------------------------------------------------------------
// Breakdown chips row
// ---------------------------------------------------------------------------

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.settlement});
  final DailyDriverSettlement settlement;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.shadowColor,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          if (settlement.carriedForwardBalance > 0) ...[
            Expanded(
              child: _BreakdownChip(
                icon: Icons.history_rounded,
                iconColor: const Color(0xFFD97706),
                label: 'Yesterday',
                value: '₹${_fmtAmount(settlement.carriedForwardBalance)}',
              ),
            ),
            Container(
              width: 1,
              height: 44,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.08),
            ),
          ],
          Expanded(
            child: _BreakdownChip(
              icon: Icons.local_shipping_rounded,
              iconColor: const Color(0xFF2563EB),
              label: 'Today',
              value: '₹${_fmtAmount(settlement.totalCollectedToday)}',
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownChip extends StatelessWidget {
  const _BreakdownChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.50),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cash-in-hand vs. COD limit
// ---------------------------------------------------------------------------

/// Shows how much of the driver's cash limit is consumed, so the settlement
/// screen answers "how much room do I have left?" alongside "what do I owe?".
///
/// Collapses to nothing when the limit isn't in play (feature disabled, no
/// limit configured, or the backend endpoint undeployed).
class _CashLimitRow extends ConsumerWidget {
  const _CashLimitRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CodLimitStatus? status = ref
        .watch(codLimitStatusProvider)
        .asData
        ?.value;
    if (status == null || !status.hasValidLimit) {
      return const SizedBox.shrink();
    }

    final Color accent = status.isBlocked
        ? const Color(0xFFDC2626)
        : status.isWarning
            ? const Color(0xFFD97706)
            : const Color(0xFF16A34A);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    color: accent,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cash in Hand',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.50),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '₹${_fmtAmount(status.cashInHand)} of '
                        '₹${_fmtAmount(status.maxLimit)}',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '₹${_fmtAmount(status.availableLimit)} left',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: status.usedFraction,
                minHeight: 6,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            if (status.isBlocked) ...[
              const SizedBox(height: 8),
              Text(
                'Settle your cash to accept more COD orders. '
                'Prepaid orders are still available.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.60),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Order Breakdown button
// ---------------------------------------------------------------------------

class _OrderBreakdownButton extends StatelessWidget {
  const _OrderBreakdownButton({required this.settlement});
  final DailyDriverSettlement settlement;

  @override
  Widget build(BuildContext context) {
    final count = settlement.settlementOrders.length;

    return InkWell(
      onTap: () => Navigator.of(context).pushNamed(
        AppRoutes.orderBreakdown,
        arguments: {
          'orders': settlement.settlementOrders,
          'date': settlement.settlementDate ?? '',
        },
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: context.scheme.primary.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: context.scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.receipt_long_rounded,
                color: context.scheme.primary,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'View Order Breakdown',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$count order${count == 1 ? '' : 's'} collected today',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.50),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status card (post-submission banners)
// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: color.withValues(alpha: 0.85),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Submitted details (read-only)
// ---------------------------------------------------------------------------

class _SubmittedDetailsCard extends StatelessWidget {
  const _SubmittedDetailsCard({required this.settlement});
  final DailyDriverSettlement settlement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.shadowColor,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transfer Details',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.45),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          _SubmittedField(
            icon: Icons.currency_rupee_rounded,
            label: 'Amount Transferred',
            value: settlement.amountTransferred != null
                ? '₹${_fmtAmount(settlement.amountTransferred!)}'
                : '—',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1),
          ),
          _SubmittedField(
            icon: Icons.tag_rounded,
            label: 'Bank Reference No.',
            value: settlement.bankTransferReference?.isNotEmpty == true
                ? settlement.bankTransferReference!
                : '—',
          ),
        ],
      ),
    );
  }
}

class _SubmittedField extends StatelessWidget {
  const _SubmittedField({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.35),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Transfer form card (Pending state)
// ---------------------------------------------------------------------------

class _TransferFormCard extends StatelessWidget {
  const _TransferFormCard({
    required this.amountController,
    required this.referenceController,
    required this.amountError,
    required this.referenceError,
    required this.submitError,
    required this.isSubmitting,
    required this.accentColor,
    required this.onSubmit,
  });

  final TextEditingController amountController;
  final TextEditingController referenceController;
  final String? amountError;
  final String? referenceError;
  final String? submitError;
  final bool isSubmitting;
  final Color accentColor;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final fieldFill = context.surfaceContainer;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.shadowColor,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.account_balance_rounded,
                  color: accentColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Transfer Details',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Amount field
          _buildFieldLabel(context, '₹ Amount Transferred'),
          const SizedBox(height: 6),
          TextField(
            controller: amountController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. 1500',
              hintStyle: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.28),
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: Text(
                  '₹',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: amountError != null
                        ? Theme.of(context).colorScheme.error
                        : accentColor,
                  ),
                ),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
              errorText: amountError,
              filled: true,
              fillColor: fieldFill,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: accentColor, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 1.5,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Reference field
          _buildFieldLabel(context, 'Bank Reference Number'),
          const SizedBox(height: 6),
          TextField(
            controller: referenceController,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. NEFT12345678',
              hintStyle: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.28),
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(
                Icons.tag_rounded,
                color: referenceError != null
                    ? Theme.of(context).colorScheme.error
                    : accentColor.withValues(alpha: 0.7),
                size: 20,
              ),
              errorText: referenceError,
              filled: true,
              fillColor: fieldFill,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: accentColor, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 1.5,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 1.5,
                ),
              ),
            ),
          ),

          // Submit error
          if (submitError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .error
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      submitError!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Submit button
          _GradientButton(
            label: 'Submit Transfer',
            icon: Icons.send_rounded,
            gradient: [accentColor, accentColor.withValues(alpha: 0.75)],
            isLoading: isSubmitting,
            onTap: isSubmitting ? null : onSubmit,
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
        letterSpacing: 0.2,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gradient submit button
// ---------------------------------------------------------------------------

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.isLoading,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final List<Color> gradient;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        gradient: onTap != null
            ? LinearGradient(colors: gradient)
            : const LinearGradient(
                colors: [Color(0xFFB0BEC5), Color(0xFF90A4AE)],
              ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: onTap != null
            ? [
                BoxShadow(
                  color: gradient.first.withValues(alpha: 0.40),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confirmation dialog row
// ---------------------------------------------------------------------------

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.50),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Delegates to the shared formatter on CodLimitStatus so the settlement screen
// and the cash-in-hand surfaces can never render the same figure differently.
String _fmtAmount(double amount) => CodLimitStatus.formatAmount(amount);
