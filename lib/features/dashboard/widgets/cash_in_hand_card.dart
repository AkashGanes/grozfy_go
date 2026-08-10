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

/// Shows the driver how much COD headroom they have left against their limit,
/// warns as they approach it, and points them at settlement once they're
/// blocked from taking further COD work.
///
/// Renders nothing at all when the limit isn't in play — feature disabled, no
/// limit configured, or the backend endpoint not yet deployed. That keeps the
/// dashboard identical to today until the backend ships.
///
/// **Used by both the dashboard and the settlement screen.** They previously
/// drew the same numbers in two different visual languages, and disagreed on
/// the colours — the settlement copy painted the healthy state green while the
/// dashboard painted it primary, and hardcoded an English blocked hint that
/// could never translate. One widget so they cannot drift again; [margin] is
/// the only thing either caller varies.
class CashInHandCard extends ConsumerWidget {
  const CashInHandCard({super.key, this.margin = EdgeInsets.zero});

  final EdgeInsets margin;

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

    return Padding(
      padding: margin,
      child: SectionCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          // The whole card leads to settlement, not just the conditional chip.
          // A driver who wants to hand cash over *before* being blocked had no
          // path to it from the dashboard at all.
          borderRadius: BorderRadius.circular(22),
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.codSettlement),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, t, status, accent),
                const SizedBox(height: 14),
                _headline(context, t, status),
                const SizedBox(height: 10),
                _SegmentedLimitBar(status: status, accent: accent),
                const SizedBox(height: 9),
                _legend(context, t, status, accent),
                if (status.isBlocked) ...[
                  const SizedBox(height: 8),
                  Text(
                    t('cash_limit_blocked_hint'),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: DashColors.textSecondary(context),
                    ),
                  ),
                ],
                if (status.isBlocked || status.isWarning) ...[
                  const SizedBox(height: 14),
                  _settleButton(context, t, accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    String Function(String) t,
    CodLimitStatus status,
    Color accent,
  ) {
    return Row(
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
    );
  }

  /// Headroom is the hero, not cash held.
  ///
  /// "How much more COD can I take?" is the only question this card exists to
  /// answer, and it used to be the 12px subtitle while the 27px figure showed a
  /// number the driver can do nothing with.
  Widget _headline(
    BuildContext context,
    String Function(String) t,
    CodLimitStatus status,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '₹${CodLimitStatus.formatAmount(status.availableLimit)}',
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: DashColors.textPrimary(context),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          t('cash_limit_available'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DashColors.textSecondary(context),
          ),
        ),
        const Spacer(),
        Text(
          '${t('cash_limit_of')} ₹${CodLimitStatus.formatAmount(status.maxLimit)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DashColors.textSecondary(context),
          ),
        ),
      ],
    );
  }

  /// Names the two things the bar is made of.
  ///
  /// `cashInHand` is `settledBalance + inFlightCod`, which are very different
  /// to a driver: cash actually in their pocket versus COD on orders they have
  /// not delivered yet. Showing only the total made "why am I blocked?"
  /// unanswerable from the card.
  Widget _legend(
    BuildContext context,
    String Function(String) t,
    CodLimitStatus status,
    Color accent,
  ) {
    final bool hasInFlight = status.inFlightCod > 0;
    final bool hasSettled = status.settledBalance > 0;
    if (!hasInFlight && !hasSettled) {
      return Text(
        t('cash_limit_none_held'),
        style: TextStyle(
          fontSize: 12,
          color: DashColors.textSecondary(context),
        ),
      );
    }

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        if (hasSettled)
          _LegendDot(
            color: accent,
            label:
                '₹${CodLimitStatus.formatAmount(status.settledBalance)} '
                '${t('cash_limit_collected')}',
          ),
        if (hasInFlight)
          _LegendDot(
            color: accent.withValues(alpha: 0.45),
            label:
                '₹${CodLimitStatus.formatAmount(status.inFlightCod)} '
                '${_inFlightSuffix(t, status.inFlightOrders)}',
          ),
      ],
    );
  }

  /// Filled, full width — deliberately the loudest thing on the card.
  ///
  /// It was a tinted chip on a 12% wash, which read as a disabled button next
  /// to the solid Active Order buttons directly below it. This appears only
  /// when the driver is near or past the limit, i.e. when they are about to
  /// stop being able to earn, so it should not look optional.
  Widget _settleButton(
    BuildContext context,
    String Function(String) t,
    Color accent,
  ) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: accent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.codSettlement),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                t('settle_now'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Falls back to the order-less wording rather than rendering "in 1 orders".
  static String _inFlightSuffix(String Function(String) t, int orders) {
    if (orders <= 0) return t('cash_limit_in_flight');
    if (orders == 1) return t('cash_limit_in_order');
    return t('cash_limit_in_orders').replaceAll('{count}', '$orders');
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
}

/// Two-tone usage bar: cash collected (solid) and undelivered COD (tinted),
/// against the limit.
///
/// Drawn by overlaying rather than laying out two flex children, so a zero-width
/// segment simply doesn't paint — `Expanded` with a flex of 0 throws.
class _SegmentedLimitBar extends StatelessWidget {
  const _SegmentedLimitBar({required this.status, required this.accent});

  static const double _height = 8;

  final CodLimitStatus status;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final double limit = status.maxLimit;
    // usedFraction already clamps; mirror it for the settled-only portion so a
    // server figure over the limit cannot overflow the track.
    final double usedFraction = status.usedFraction;
    final double settledFraction = limit <= 0
        ? 0
        : (status.settledBalance / limit).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: _height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: DashColors.subtleFill(context)),
            ),
            // Total exposure first, then the collected portion painted over its
            // left edge — the difference reads as the in-flight segment.
            if (usedFraction > 0)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: usedFraction,
                  child: ColoredBox(color: accent.withValues(alpha: 0.45)),
                ),
              ),
            if (settledFraction > 0)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: settledFraction,
                  child: ColoredBox(color: accent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: DashColors.textSecondary(context),
          ),
        ),
      ],
    );
  }
}
