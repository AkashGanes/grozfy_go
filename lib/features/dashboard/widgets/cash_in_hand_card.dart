import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_routes.dart';
import '../../../core/state/providers.dart';
import '../../../core/theme/context_colors.dart';
import '../../cod_settlement/model/cod_limit_status.dart';
import '../../cod_settlement/providers/settlement_provider.dart';
import 'dashboard_colors.dart';
import 'section_card.dart';
import 'status_pill.dart';

/// Shows the driver how much COD cash they are holding against their configured
/// limit, warns as they approach it, and points them at settlement once they're
/// blocked from taking further COD work.
///
/// Renders nothing at all when the limit isn't in play — feature disabled, no
/// limit configured, or the backend endpoint not yet deployed. That keeps the
/// dashboard identical to today until the backend ships.
class CashInHandCard extends ConsumerWidget {
  const CashInHandCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CodLimitStatus? status = ref
        .watch(codLimitStatusProvider)
        .asData
        ?.value;

    if (status == null || !status.hasValidLimit) {
      return const SizedBox.shrink();
    }

    final String Function(String) t = ref.read(appControllerProvider).t;
    final Color accent = _accent(context, status);

    // Owns its bottom spacing so the dashboard needs no conditional gap around
    // it — when the limit isn't in play this widget collapses to nothing.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  t('cash_in_hand'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: DashColors.textPrimary(context),
                  ),
                ),
              ),
              StatusPill(
                label: _pillLabel(t, status),
                tone: _tone(status),
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Held vs. limit.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₹${CodLimitStatus.formatAmount(status.cashInHand)}',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: DashColors.textPrimary(context),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${t('cash_limit_of')} ₹${CodLimitStatus.formatAmount(status.maxLimit)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DashColors.textSecondary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: status.usedFraction,
              minHeight: 7,
              backgroundColor: DashColors.subtleFill(context),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 9),

          Text(
            _subtitle(t, status),
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: DashColors.textSecondary(context),
            ),
          ),

          if (status.isBlocked || status.isWarning) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.codSettlement),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    child: Text(
                      t('settle_now'),
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ],
          ],
        ),
      ),
    );
  }

  /// Blocked reads as an error, warning as a caution, otherwise it's just
  /// information — the driver isn't doing anything wrong by holding cash.
  static Color _accent(BuildContext context, CodLimitStatus status) {
    if (status.isBlocked) return context.danger;
    if (status.isWarning) return context.warning;
    return context.scheme.primary;
  }

  static StatusPillTone _tone(CodLimitStatus status) {
    if (status.isBlocked) return StatusPillTone.danger;
    if (status.isWarning) return StatusPillTone.warning;
    return StatusPillTone.neutral;
  }

  static String _pillLabel(String Function(String) t, CodLimitStatus status) {
    if (status.isBlocked) return t('cash_limit_reached');
    if (status.isWarning) return t('cash_limit_warning');
    return t('cash_limit_ok');
  }

  static String _subtitle(String Function(String) t, CodLimitStatus status) {
    if (status.isBlocked) return t('cash_limit_blocked_hint');

    final String available =
        '₹${CodLimitStatus.formatAmount(status.availableLimit)} ${t('cash_limit_available')}';
    if (status.inFlightCod <= 0) return available;

    return '$available · ₹${CodLimitStatus.formatAmount(status.inFlightCod)} '
        '${t('cash_limit_in_flight')}';
  }
}
