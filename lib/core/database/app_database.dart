import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'partner_timing_log_dao.dart';

part 'app_database.g.dart';

class PartnerTimingLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get eventUuid => text().unique()();
  TextColumn get partner => text()();
  TextColumn get eventType => text()();
  // ISO-8601 string — used for oldest-first ordering during sync
  TextColumn get eventTime => text()();
  TextColumn get tripName => text().nullable()();
  TextColumn get stopName => text().nullable()();
  TextColumn get remarks => text().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  TextColumn get createdAt => text()();
}

@DriftDatabase(tables: [PartnerTimingLogs], daos: [PartnerTimingLogDao])
class FlowFleetDatabase extends _$FlowFleetDatabase {
  FlowFleetDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(path.join(dbFolder.path, 'flowfleet.db'));
    return NativeDatabase.createInBackground(file);
  });
}
