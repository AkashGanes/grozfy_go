// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PartnerTimingLogsTable extends PartnerTimingLogs
    with TableInfo<$PartnerTimingLogsTable, PartnerTimingLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PartnerTimingLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _eventUuidMeta = const VerificationMeta(
    'eventUuid',
  );
  @override
  late final GeneratedColumn<String> eventUuid = GeneratedColumn<String>(
    'event_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _partnerMeta = const VerificationMeta(
    'partner',
  );
  @override
  late final GeneratedColumn<String> partner = GeneratedColumn<String>(
    'partner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventTypeMeta = const VerificationMeta(
    'eventType',
  );
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
    'event_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventTimeMeta = const VerificationMeta(
    'eventTime',
  );
  @override
  late final GeneratedColumn<String> eventTime = GeneratedColumn<String>(
    'event_time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tripNameMeta = const VerificationMeta(
    'tripName',
  );
  @override
  late final GeneratedColumn<String> tripName = GeneratedColumn<String>(
    'trip_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stopNameMeta = const VerificationMeta(
    'stopName',
  );
  @override
  late final GeneratedColumn<String> stopName = GeneratedColumn<String>(
    'stop_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remarksMeta = const VerificationMeta(
    'remarks',
  );
  @override
  late final GeneratedColumn<String> remarks = GeneratedColumn<String>(
    'remarks',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isSyncedMeta = const VerificationMeta(
    'isSynced',
  );
  @override
  late final GeneratedColumn<bool> isSynced = GeneratedColumn<bool>(
    'is_synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    eventUuid,
    partner,
    eventType,
    eventTime,
    tripName,
    stopName,
    remarks,
    isSynced,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'partner_timing_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<PartnerTimingLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('event_uuid')) {
      context.handle(
        _eventUuidMeta,
        eventUuid.isAcceptableOrUnknown(data['event_uuid']!, _eventUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_eventUuidMeta);
    }
    if (data.containsKey('partner')) {
      context.handle(
        _partnerMeta,
        partner.isAcceptableOrUnknown(data['partner']!, _partnerMeta),
      );
    } else if (isInserting) {
      context.missing(_partnerMeta);
    }
    if (data.containsKey('event_type')) {
      context.handle(
        _eventTypeMeta,
        eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('event_time')) {
      context.handle(
        _eventTimeMeta,
        eventTime.isAcceptableOrUnknown(data['event_time']!, _eventTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTimeMeta);
    }
    if (data.containsKey('trip_name')) {
      context.handle(
        _tripNameMeta,
        tripName.isAcceptableOrUnknown(data['trip_name']!, _tripNameMeta),
      );
    }
    if (data.containsKey('stop_name')) {
      context.handle(
        _stopNameMeta,
        stopName.isAcceptableOrUnknown(data['stop_name']!, _stopNameMeta),
      );
    }
    if (data.containsKey('remarks')) {
      context.handle(
        _remarksMeta,
        remarks.isAcceptableOrUnknown(data['remarks']!, _remarksMeta),
      );
    }
    if (data.containsKey('is_synced')) {
      context.handle(
        _isSyncedMeta,
        isSynced.isAcceptableOrUnknown(data['is_synced']!, _isSyncedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PartnerTimingLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PartnerTimingLog(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      eventUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_uuid'],
      )!,
      partner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}partner'],
      )!,
      eventType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      eventTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_time'],
      )!,
      tripName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_name'],
      ),
      stopName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stop_name'],
      ),
      remarks: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remarks'],
      ),
      isSynced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_synced'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PartnerTimingLogsTable createAlias(String alias) {
    return $PartnerTimingLogsTable(attachedDatabase, alias);
  }
}

class PartnerTimingLog extends DataClass
    implements Insertable<PartnerTimingLog> {
  final int id;
  final String eventUuid;
  final String partner;
  final String eventType;
  final String eventTime;
  final String? tripName;
  final String? stopName;
  final String? remarks;
  final bool isSynced;
  final String createdAt;
  const PartnerTimingLog({
    required this.id,
    required this.eventUuid,
    required this.partner,
    required this.eventType,
    required this.eventTime,
    this.tripName,
    this.stopName,
    this.remarks,
    required this.isSynced,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['event_uuid'] = Variable<String>(eventUuid);
    map['partner'] = Variable<String>(partner);
    map['event_type'] = Variable<String>(eventType);
    map['event_time'] = Variable<String>(eventTime);
    if (!nullToAbsent || tripName != null) {
      map['trip_name'] = Variable<String>(tripName);
    }
    if (!nullToAbsent || stopName != null) {
      map['stop_name'] = Variable<String>(stopName);
    }
    if (!nullToAbsent || remarks != null) {
      map['remarks'] = Variable<String>(remarks);
    }
    map['is_synced'] = Variable<bool>(isSynced);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  PartnerTimingLogsCompanion toCompanion(bool nullToAbsent) {
    return PartnerTimingLogsCompanion(
      id: Value(id),
      eventUuid: Value(eventUuid),
      partner: Value(partner),
      eventType: Value(eventType),
      eventTime: Value(eventTime),
      tripName: tripName == null && nullToAbsent
          ? const Value.absent()
          : Value(tripName),
      stopName: stopName == null && nullToAbsent
          ? const Value.absent()
          : Value(stopName),
      remarks: remarks == null && nullToAbsent
          ? const Value.absent()
          : Value(remarks),
      isSynced: Value(isSynced),
      createdAt: Value(createdAt),
    );
  }

  factory PartnerTimingLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PartnerTimingLog(
      id: serializer.fromJson<int>(json['id']),
      eventUuid: serializer.fromJson<String>(json['eventUuid']),
      partner: serializer.fromJson<String>(json['partner']),
      eventType: serializer.fromJson<String>(json['eventType']),
      eventTime: serializer.fromJson<String>(json['eventTime']),
      tripName: serializer.fromJson<String?>(json['tripName']),
      stopName: serializer.fromJson<String?>(json['stopName']),
      remarks: serializer.fromJson<String?>(json['remarks']),
      isSynced: serializer.fromJson<bool>(json['isSynced']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'eventUuid': serializer.toJson<String>(eventUuid),
      'partner': serializer.toJson<String>(partner),
      'eventType': serializer.toJson<String>(eventType),
      'eventTime': serializer.toJson<String>(eventTime),
      'tripName': serializer.toJson<String?>(tripName),
      'stopName': serializer.toJson<String?>(stopName),
      'remarks': serializer.toJson<String?>(remarks),
      'isSynced': serializer.toJson<bool>(isSynced),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  PartnerTimingLog copyWith({
    int? id,
    String? eventUuid,
    String? partner,
    String? eventType,
    String? eventTime,
    Value<String?> tripName = const Value.absent(),
    Value<String?> stopName = const Value.absent(),
    Value<String?> remarks = const Value.absent(),
    bool? isSynced,
    String? createdAt,
  }) => PartnerTimingLog(
    id: id ?? this.id,
    eventUuid: eventUuid ?? this.eventUuid,
    partner: partner ?? this.partner,
    eventType: eventType ?? this.eventType,
    eventTime: eventTime ?? this.eventTime,
    tripName: tripName.present ? tripName.value : this.tripName,
    stopName: stopName.present ? stopName.value : this.stopName,
    remarks: remarks.present ? remarks.value : this.remarks,
    isSynced: isSynced ?? this.isSynced,
    createdAt: createdAt ?? this.createdAt,
  );
  PartnerTimingLog copyWithCompanion(PartnerTimingLogsCompanion data) {
    return PartnerTimingLog(
      id: data.id.present ? data.id.value : this.id,
      eventUuid: data.eventUuid.present ? data.eventUuid.value : this.eventUuid,
      partner: data.partner.present ? data.partner.value : this.partner,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      eventTime: data.eventTime.present ? data.eventTime.value : this.eventTime,
      tripName: data.tripName.present ? data.tripName.value : this.tripName,
      stopName: data.stopName.present ? data.stopName.value : this.stopName,
      remarks: data.remarks.present ? data.remarks.value : this.remarks,
      isSynced: data.isSynced.present ? data.isSynced.value : this.isSynced,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PartnerTimingLog(')
          ..write('id: $id, ')
          ..write('eventUuid: $eventUuid, ')
          ..write('partner: $partner, ')
          ..write('eventType: $eventType, ')
          ..write('eventTime: $eventTime, ')
          ..write('tripName: $tripName, ')
          ..write('stopName: $stopName, ')
          ..write('remarks: $remarks, ')
          ..write('isSynced: $isSynced, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    eventUuid,
    partner,
    eventType,
    eventTime,
    tripName,
    stopName,
    remarks,
    isSynced,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PartnerTimingLog &&
          other.id == this.id &&
          other.eventUuid == this.eventUuid &&
          other.partner == this.partner &&
          other.eventType == this.eventType &&
          other.eventTime == this.eventTime &&
          other.tripName == this.tripName &&
          other.stopName == this.stopName &&
          other.remarks == this.remarks &&
          other.isSynced == this.isSynced &&
          other.createdAt == this.createdAt);
}

class PartnerTimingLogsCompanion extends UpdateCompanion<PartnerTimingLog> {
  final Value<int> id;
  final Value<String> eventUuid;
  final Value<String> partner;
  final Value<String> eventType;
  final Value<String> eventTime;
  final Value<String?> tripName;
  final Value<String?> stopName;
  final Value<String?> remarks;
  final Value<bool> isSynced;
  final Value<String> createdAt;
  const PartnerTimingLogsCompanion({
    this.id = const Value.absent(),
    this.eventUuid = const Value.absent(),
    this.partner = const Value.absent(),
    this.eventType = const Value.absent(),
    this.eventTime = const Value.absent(),
    this.tripName = const Value.absent(),
    this.stopName = const Value.absent(),
    this.remarks = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  PartnerTimingLogsCompanion.insert({
    this.id = const Value.absent(),
    required String eventUuid,
    required String partner,
    required String eventType,
    required String eventTime,
    this.tripName = const Value.absent(),
    this.stopName = const Value.absent(),
    this.remarks = const Value.absent(),
    this.isSynced = const Value.absent(),
    required String createdAt,
  }) : eventUuid = Value(eventUuid),
       partner = Value(partner),
       eventType = Value(eventType),
       eventTime = Value(eventTime),
       createdAt = Value(createdAt);
  static Insertable<PartnerTimingLog> custom({
    Expression<int>? id,
    Expression<String>? eventUuid,
    Expression<String>? partner,
    Expression<String>? eventType,
    Expression<String>? eventTime,
    Expression<String>? tripName,
    Expression<String>? stopName,
    Expression<String>? remarks,
    Expression<bool>? isSynced,
    Expression<String>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (eventUuid != null) 'event_uuid': eventUuid,
      if (partner != null) 'partner': partner,
      if (eventType != null) 'event_type': eventType,
      if (eventTime != null) 'event_time': eventTime,
      if (tripName != null) 'trip_name': tripName,
      if (stopName != null) 'stop_name': stopName,
      if (remarks != null) 'remarks': remarks,
      if (isSynced != null) 'is_synced': isSynced,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  PartnerTimingLogsCompanion copyWith({
    Value<int>? id,
    Value<String>? eventUuid,
    Value<String>? partner,
    Value<String>? eventType,
    Value<String>? eventTime,
    Value<String?>? tripName,
    Value<String?>? stopName,
    Value<String?>? remarks,
    Value<bool>? isSynced,
    Value<String>? createdAt,
  }) {
    return PartnerTimingLogsCompanion(
      id: id ?? this.id,
      eventUuid: eventUuid ?? this.eventUuid,
      partner: partner ?? this.partner,
      eventType: eventType ?? this.eventType,
      eventTime: eventTime ?? this.eventTime,
      tripName: tripName ?? this.tripName,
      stopName: stopName ?? this.stopName,
      remarks: remarks ?? this.remarks,
      isSynced: isSynced ?? this.isSynced,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (eventUuid.present) {
      map['event_uuid'] = Variable<String>(eventUuid.value);
    }
    if (partner.present) {
      map['partner'] = Variable<String>(partner.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (eventTime.present) {
      map['event_time'] = Variable<String>(eventTime.value);
    }
    if (tripName.present) {
      map['trip_name'] = Variable<String>(tripName.value);
    }
    if (stopName.present) {
      map['stop_name'] = Variable<String>(stopName.value);
    }
    if (remarks.present) {
      map['remarks'] = Variable<String>(remarks.value);
    }
    if (isSynced.present) {
      map['is_synced'] = Variable<bool>(isSynced.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PartnerTimingLogsCompanion(')
          ..write('id: $id, ')
          ..write('eventUuid: $eventUuid, ')
          ..write('partner: $partner, ')
          ..write('eventType: $eventType, ')
          ..write('eventTime: $eventTime, ')
          ..write('tripName: $tripName, ')
          ..write('stopName: $stopName, ')
          ..write('remarks: $remarks, ')
          ..write('isSynced: $isSynced, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$FlowFleetDatabase extends GeneratedDatabase {
  _$FlowFleetDatabase(QueryExecutor e) : super(e);
  $FlowFleetDatabaseManager get managers => $FlowFleetDatabaseManager(this);
  late final $PartnerTimingLogsTable partnerTimingLogs =
      $PartnerTimingLogsTable(this);
  late final PartnerTimingLogDao partnerTimingLogDao = PartnerTimingLogDao(
    this as FlowFleetDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [partnerTimingLogs];
}

typedef $$PartnerTimingLogsTableCreateCompanionBuilder =
    PartnerTimingLogsCompanion Function({
      Value<int> id,
      required String eventUuid,
      required String partner,
      required String eventType,
      required String eventTime,
      Value<String?> tripName,
      Value<String?> stopName,
      Value<String?> remarks,
      Value<bool> isSynced,
      required String createdAt,
    });
typedef $$PartnerTimingLogsTableUpdateCompanionBuilder =
    PartnerTimingLogsCompanion Function({
      Value<int> id,
      Value<String> eventUuid,
      Value<String> partner,
      Value<String> eventType,
      Value<String> eventTime,
      Value<String?> tripName,
      Value<String?> stopName,
      Value<String?> remarks,
      Value<bool> isSynced,
      Value<String> createdAt,
    });

class $$PartnerTimingLogsTableFilterComposer
    extends Composer<_$FlowFleetDatabase, $PartnerTimingLogsTable> {
  $$PartnerTimingLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventUuid => $composableBuilder(
    column: $table.eventUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get partner => $composableBuilder(
    column: $table.partner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventTime => $composableBuilder(
    column: $table.eventTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tripName => $composableBuilder(
    column: $table.tripName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stopName => $composableBuilder(
    column: $table.stopName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remarks => $composableBuilder(
    column: $table.remarks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PartnerTimingLogsTableOrderingComposer
    extends Composer<_$FlowFleetDatabase, $PartnerTimingLogsTable> {
  $$PartnerTimingLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventUuid => $composableBuilder(
    column: $table.eventUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get partner => $composableBuilder(
    column: $table.partner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventTime => $composableBuilder(
    column: $table.eventTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tripName => $composableBuilder(
    column: $table.tripName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stopName => $composableBuilder(
    column: $table.stopName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remarks => $composableBuilder(
    column: $table.remarks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PartnerTimingLogsTableAnnotationComposer
    extends Composer<_$FlowFleetDatabase, $PartnerTimingLogsTable> {
  $$PartnerTimingLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get eventUuid =>
      $composableBuilder(column: $table.eventUuid, builder: (column) => column);

  GeneratedColumn<String> get partner =>
      $composableBuilder(column: $table.partner, builder: (column) => column);

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<String> get eventTime =>
      $composableBuilder(column: $table.eventTime, builder: (column) => column);

  GeneratedColumn<String> get tripName =>
      $composableBuilder(column: $table.tripName, builder: (column) => column);

  GeneratedColumn<String> get stopName =>
      $composableBuilder(column: $table.stopName, builder: (column) => column);

  GeneratedColumn<String> get remarks =>
      $composableBuilder(column: $table.remarks, builder: (column) => column);

  GeneratedColumn<bool> get isSynced =>
      $composableBuilder(column: $table.isSynced, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PartnerTimingLogsTableTableManager
    extends
        RootTableManager<
          _$FlowFleetDatabase,
          $PartnerTimingLogsTable,
          PartnerTimingLog,
          $$PartnerTimingLogsTableFilterComposer,
          $$PartnerTimingLogsTableOrderingComposer,
          $$PartnerTimingLogsTableAnnotationComposer,
          $$PartnerTimingLogsTableCreateCompanionBuilder,
          $$PartnerTimingLogsTableUpdateCompanionBuilder,
          (
            PartnerTimingLog,
            BaseReferences<
              _$FlowFleetDatabase,
              $PartnerTimingLogsTable,
              PartnerTimingLog
            >,
          ),
          PartnerTimingLog,
          PrefetchHooks Function()
        > {
  $$PartnerTimingLogsTableTableManager(
    _$FlowFleetDatabase db,
    $PartnerTimingLogsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PartnerTimingLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PartnerTimingLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PartnerTimingLogsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> eventUuid = const Value.absent(),
                Value<String> partner = const Value.absent(),
                Value<String> eventType = const Value.absent(),
                Value<String> eventTime = const Value.absent(),
                Value<String?> tripName = const Value.absent(),
                Value<String?> stopName = const Value.absent(),
                Value<String?> remarks = const Value.absent(),
                Value<bool> isSynced = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
              }) => PartnerTimingLogsCompanion(
                id: id,
                eventUuid: eventUuid,
                partner: partner,
                eventType: eventType,
                eventTime: eventTime,
                tripName: tripName,
                stopName: stopName,
                remarks: remarks,
                isSynced: isSynced,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String eventUuid,
                required String partner,
                required String eventType,
                required String eventTime,
                Value<String?> tripName = const Value.absent(),
                Value<String?> stopName = const Value.absent(),
                Value<String?> remarks = const Value.absent(),
                Value<bool> isSynced = const Value.absent(),
                required String createdAt,
              }) => PartnerTimingLogsCompanion.insert(
                id: id,
                eventUuid: eventUuid,
                partner: partner,
                eventType: eventType,
                eventTime: eventTime,
                tripName: tripName,
                stopName: stopName,
                remarks: remarks,
                isSynced: isSynced,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PartnerTimingLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$FlowFleetDatabase,
      $PartnerTimingLogsTable,
      PartnerTimingLog,
      $$PartnerTimingLogsTableFilterComposer,
      $$PartnerTimingLogsTableOrderingComposer,
      $$PartnerTimingLogsTableAnnotationComposer,
      $$PartnerTimingLogsTableCreateCompanionBuilder,
      $$PartnerTimingLogsTableUpdateCompanionBuilder,
      (
        PartnerTimingLog,
        BaseReferences<
          _$FlowFleetDatabase,
          $PartnerTimingLogsTable,
          PartnerTimingLog
        >,
      ),
      PartnerTimingLog,
      PrefetchHooks Function()
    >;

class $FlowFleetDatabaseManager {
  final _$FlowFleetDatabase _db;
  $FlowFleetDatabaseManager(this._db);
  $$PartnerTimingLogsTableTableManager get partnerTimingLogs =>
      $$PartnerTimingLogsTableTableManager(_db, _db.partnerTimingLogs);
}
