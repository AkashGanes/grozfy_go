import 'package:drift/drift.dart';

import 'app_database.dart';

part 'partner_timing_log_dao.g.dart';

@DriftAccessor(tables: [PartnerTimingLogs])
class PartnerTimingLogDao extends DatabaseAccessor<FlowFleetDatabase>
    with _$PartnerTimingLogDaoMixin {
  PartnerTimingLogDao(super.db);

  Future<void> insertEvent(PartnerTimingLogsCompanion event) {
    return into(partnerTimingLogs).insertOnConflictUpdate(event);
  }

  Future<List<PartnerTimingLog>> getUnsyncedEvents() {
    return (select(partnerTimingLogs)
          ..where((t) => t.isSynced.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.eventTime)]))
        .get();
  }

  Future<void> markAsSynced(String eventUuid) {
    return (update(partnerTimingLogs)
          ..where((t) => t.eventUuid.equals(eventUuid)))
        .write(const PartnerTimingLogsCompanion(isSynced: Value(true)));
  }

  Future<List<PartnerTimingLog>> getEventsByTrip(String tripName) {
    return (select(partnerTimingLogs)
          ..where((t) => t.tripName.equals(tripName))
          ..orderBy([(t) => OrderingTerm.asc(t.eventTime)]))
        .get();
  }

  Future<List<PartnerTimingLog>> getEventsInRange(
    DateTime start,
    DateTime end, {
    String? partner,
  }) {
    final startStr = start.toIso8601String();
    final endStr = end.toIso8601String();
    return (select(partnerTimingLogs)
          ..where(
            (t) =>
                t.eventTime.isBiggerOrEqualValue(startStr) &
                t.eventTime.isSmallerThanValue(endStr) &
                (partner != null && partner.isNotEmpty
                    ? t.partner.equals(partner)
                    : const Constant(true)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.eventTime)]))
        .get();
  }

  Future<List<PartnerTimingLog>> getAllEvents({String? partner}) {
    return (select(partnerTimingLogs)
          ..where(
            (t) => partner != null && partner.isNotEmpty
                ? t.partner.equals(partner)
                : const Constant(true),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.eventTime)]))
        .get();
  }

  Future<void> migrateEventTypes() async {
    await (update(partnerTimingLogs)
          ..where((t) => t.eventType.equals('login')))
        .write(const PartnerTimingLogsCompanion(eventType: Value('driver_login')));

    await (update(partnerTimingLogs)
          ..where((t) => t.eventType.equals('logout')))
        .write(const PartnerTimingLogsCompanion(eventType: Value('driver_logout')));
  }
}

class TimingEventType {
  TimingEventType._();

  static const String login = 'driver_login';
  static const String logout = 'driver_logout';
  static const String tripAccepted = 'trip_accepted';
  static const String pickupReached = 'pickup_reached';
  static const String pickedUp = 'picked_up';
  static const String stopDelivered = 'stop_delivered';
  static const String stopFailed = 'stop_failed';
  static const String tripCompleted = 'trip_completed';
}
