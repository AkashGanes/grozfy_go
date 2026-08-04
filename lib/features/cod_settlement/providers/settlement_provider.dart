import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/cod_limit_status.dart';
import '../model/daily_driver_settlement.dart';
import '../repository/cod_settlement_repository.dart';

final settlementProvider = FutureProvider<DailyDriverSettlement?>((ref) async {
  final settlement = await CodSettlementRepository().getDriverSettlementToday();
  return settlement.exists ? settlement : null;
});

/// The driver's cash-in-hand exposure vs. their COD limit.
///
/// Null when the feature is undeployed, disabled, or unreachable — every
/// consumer treats null as "no limit in play" and renders/behaves exactly as it
/// did before the feature existed.
final codLimitStatusProvider = FutureProvider<CodLimitStatus?>((ref) async {
  return CodSettlementRepository().getCodLimitStatusOrNull();
});

/// True when the driver has a pending settlement that needs attention.
/// Drives the red dot badge on the "More" nav tab.
final settlementBadgeProvider = Provider<bool>((ref) {
  return ref.watch(settlementProvider).maybeWhen(
    data: (s) => s != null && s.status == 'Pending',
    orElse: () => false,
  );
});
