import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/daily_driver_settlement.dart';
import '../repository/cod_settlement_repository.dart';

final settlementProvider = FutureProvider<DailyDriverSettlement?>((ref) async {
  final settlement = await CodSettlementRepository().getDriverSettlementToday();
  return settlement.exists ? settlement : null;
});

/// True when the driver has a pending settlement that needs attention.
/// Drives the red dot badge on the "More" nav tab.
final settlementBadgeProvider = Provider<bool>((ref) {
  return ref.watch(settlementProvider).maybeWhen(
    data: (s) => s != null && s.status == 'Pending',
    orElse: () => false,
  );
});
