import 'package:flutter/material.dart';

class ExternalDelivery {
  const ExternalDelivery({
    required this.name,
    required this.storeUrl,
    required this.storeName,
    required this.customerName,
    required this.status,
    required this.creation,
    required this.modified,
  });

  final String name;
  final String storeUrl;
  final String storeName;
  final String customerName;
  final String status;
  final String creation;
  final String modified;

  factory ExternalDelivery.fromJson(Map<String, dynamic> m) {
    return ExternalDelivery(
      name: (m['name'] ?? '').toString(),
      storeUrl: (m['store_url'] ?? '').toString(),
      storeName: (m['store_name'] ?? '').toString(),
      customerName: (m['customer_name'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      creation: (m['creation'] ?? '').toString(),
      modified: (m['modified'] ?? '').toString(),
    );
  }

  factory ExternalDelivery.fromRow(List<String> keys, List<dynamic> row) {
    final m = <String, dynamic>{
      for (int i = 0; i < keys.length; i++) keys[i]: row[i],
    };
    return ExternalDelivery.fromJson(m);
  }
}

class ExternalDeliveryTrip {
  const ExternalDeliveryTrip({
    required this.name,
    required this.driver,
    required this.status,
    required this.tripDate,
    required this.docstatus,
    required this.totalStops,
    required this.completedStops,
    required this.totalDistanceKm,
    required this.startedAt,
    required this.completedAt,
    required this.stops,
  });

  final String name;
  final String driver;
  final String status;
  final String tripDate;
  final int docstatus;
  final int totalStops;
  final int completedStops;
  final double totalDistanceKm;
  final String startedAt;
  final String completedAt;
  final List<ExternalDeliveryTripStop> stops;

  factory ExternalDeliveryTrip.fromJson(Map<String, dynamic> m) {
    final rawStops = m['stops'];
    return ExternalDeliveryTrip(
      name: (m['name'] ?? '').toString(),
      driver: (m['driver'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      tripDate: (m['trip_date'] ?? '').toString(),
      docstatus: (m['docstatus'] as num?)?.toInt() ?? 0,
      totalStops: (m['total_stops'] as num?)?.toInt() ?? 0,
      completedStops: (m['completes_stops'] as num?)?.toInt() ?? 0,
      totalDistanceKm: (m['total_distancekm'] as num?)?.toDouble() ?? 0,
      startedAt: (m['started_at'] ?? '').toString(),
      completedAt: (m['completed_at'] ?? '').toString(),
      stops: rawStops is List
          ? rawStops
                .whereType<Map>()
                .map(
                  (e) => ExternalDeliveryTripStop.fromJson(
                    e.cast<String, dynamic>(),
                  ),
                )
                .toList()
          : const [],
    );
  }
}

class ExternalDeliveryTripStop {
  const ExternalDeliveryTripStop({
    required this.stop,
    required this.externalDelivery,
    required this.customer,
    required this.address,
    required this.mobile,
    required this.status,
    required this.deliveredAt,
    required this.notes,
  });

  final int stop;
  final String externalDelivery;
  final String customer;
  final String address;
  final String mobile;
  final String status;
  final String deliveredAt;
  final String notes;

  factory ExternalDeliveryTripStop.fromJson(Map<String, dynamic> m) {
    return ExternalDeliveryTripStop(
      stop: (m['stop'] as num?)?.toInt() ?? 0,
      externalDelivery: (m['external_delivery'] ?? '').toString(),
      customer: (m['customer'] ?? '').toString(),
      address: (m['address'] ?? '').toString(),
      mobile: (m['mobile'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      deliveredAt: (m['delivered_at'] ?? '').toString(),
      notes: (m['notes'] ?? '').toString(),
    );
  }
}

class ExternalDeliveryTripSummary {
  const ExternalDeliveryTripSummary({
    required this.name,
    required this.driver,
    required this.status,
    required this.docstatus,
    required this.tripDate,
    required this.totalStops,
    required this.completedStops,
    required this.modified,
  });

  final String name;
  final String driver;
  final String status;
  final int docstatus;
  final String tripDate;
  final int totalStops;
  final int completedStops;
  final String modified;

  factory ExternalDeliveryTripSummary.fromJson(Map<String, dynamic> m) {
    return ExternalDeliveryTripSummary(
      name: (m['name'] ?? '').toString(),
      driver: (m['driver'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      docstatus: (m['docstatus'] as num?)?.toInt() ?? 0,
      tripDate: (m['trip_date'] ?? '').toString(),
      totalStops: (m['total_stops'] as num?)?.toInt() ?? 0,
      completedStops: (m['completes_stops'] as num?)?.toInt() ?? 0,
      modified: (m['modified'] ?? '').toString(),
    );
  }
}

sealed class TripListItem {}

class DriverHeader extends TripListItem {
  DriverHeader(this.driver);
  final String driver;
}

class TripRow extends TripListItem {
  TripRow(this.trip);
  final ExternalDeliveryTripSummary trip;
}

sealed class LocationListItem {}

class StoreHeader extends LocationListItem {
  StoreHeader(this.storeName);
  final String storeName;
}

class OrderRow extends LocationListItem {
  OrderRow(this.order);
  final ExternalDelivery order;
}

extension ExternalDeliveryStatusColor on String {
  Color get statusColor => switch (this) {
    'Delivered' => const Color(0xFF2E7D32),
    'Added to Trip' => const Color(0xFFE65100),
    'Pending' => const Color(0xFF757575),
    _ => const Color(0xFF757575),
  };
}
