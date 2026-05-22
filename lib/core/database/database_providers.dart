import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'partner_timing_log_dao.dart';

final flowFleetDatabaseProvider = Provider<FlowFleetDatabase>((ref) {
  final db = FlowFleetDatabase();
  ref.onDispose(db.close);
  return db;
});

final partnerTimingLogDaoProvider = Provider<PartnerTimingLogDao>((ref) {
  return ref.watch(flowFleetDatabaseProvider).partnerTimingLogDao;
});
