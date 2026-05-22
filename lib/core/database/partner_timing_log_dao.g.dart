// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'partner_timing_log_dao.dart';

// ignore_for_file: type=lint
mixin _$PartnerTimingLogDaoMixin on DatabaseAccessor<FlowFleetDatabase> {
  $PartnerTimingLogsTable get partnerTimingLogs =>
      attachedDatabase.partnerTimingLogs;
  PartnerTimingLogDaoManager get managers => PartnerTimingLogDaoManager(this);
}

class PartnerTimingLogDaoManager {
  final _$PartnerTimingLogDaoMixin _db;
  PartnerTimingLogDaoManager(this._db);
  $$PartnerTimingLogsTableTableManager get partnerTimingLogs =>
      $$PartnerTimingLogsTableTableManager(
        _db.attachedDatabase,
        _db.partnerTimingLogs,
      );
}
