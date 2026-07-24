import 'package:flutter/material.dart';

import '../../../core/localization/localized_text.dart';

class ExternalDelivery {
  const ExternalDelivery({
    required this.name,
    required this.storeUrl,
    required this.storeName,
    required this.customerName,
    required this.status,
    required this.creation,
    required this.modified,
    this.deliveryAddress,
    this.failureReasonCode = '',
    this.deliveryNotes = '',
    this.latitude,
    this.longitude,
    this.distanceKm,
  });

  final String name;
  final String storeUrl;
  final String storeName;
  final String customerName;
  final String status;
  final String creation;
  final String modified;
  final String? deliveryAddress;
  final String failureReasonCode;
  final String deliveryNotes;
  // Delivery location. Only populated when the listing request includes the geo
  // fields (used for the delivery-radius filter); otherwise null.
  final double? latitude;
  final double? longitude;
  // Server-computed straight-line distance (km) from the driver to this
  // delivery. Only populated by the radius-aware `list_available_deliveries`
  // feed; null for records from the generic list endpoint.
  final double? distanceKm;

  factory ExternalDelivery.fromJson(Map<String, dynamic> m) {
    return ExternalDelivery(
      name: (m['name'] ?? '').toString(),
      storeUrl: (m['store_url'] ?? '').toString(),
      storeName: (m['store_name'] ?? '').toString(),
      customerName: (m['customer_name'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      creation: (m['creation'] ?? '').toString(),
      modified: (m['modified'] ?? '').toString(),
      deliveryAddress:
          m['delivery_address']?.toString().trim().isNotEmpty == true
          ? m['delivery_address'].toString().trim()
          : null,
      failureReasonCode: (m['failure_reason_code'] ?? '').toString(),
      deliveryNotes: (m['delivery_notes'] ?? '').toString(),
      latitude: (m['latitude'] as num?)?.toDouble(),
      longitude: (m['longitude'] as num?)?.toDouble(),
      distanceKm: (m['distance_km'] as num?)?.toDouble(),
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
    required this.tripNotes,
    required this.docstatus,
    required this.totalStops,
    required this.completedStops,
    required this.totalDistanceKm,
    required this.startedAt,
    required this.completedAt,
    required this.stops,
    required this.rawFields,
    this.pickupStops = const [],
  });

  final String name;
  final String driver;
  final String status;
  final String tripDate;
  final String tripNotes;
  final int docstatus;
  final int totalStops;
  final int completedStops;
  final double totalDistanceKm;
  final String startedAt;
  final String completedAt;
  final List<ExternalDeliveryTripStop> stops;
  final List<PickupTripStop> pickupStops;
  final Map<String, dynamic> rawFields;

  /// True when this trip was created as a return-to-store trip.
  bool get isReturnTrip =>
      tripNotes.toLowerCase().startsWith('return_trip_for:');

  String localizedTripNotes(String languageCode) {
    return LocalizedText.resolveTripNotes(languageCode, tripNotes);
  }

  factory ExternalDeliveryTrip.fromJson(Map<String, dynamic> m) {
    final rawStops = m['stops'];
    final rawPickupStops = m['pickup_stops'];
    final raw = Map<String, dynamic>.from(m);
    return ExternalDeliveryTrip(
      name: (m['name'] ?? '').toString(),
      driver: (m['driver'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      tripDate: (m['trip_date'] ?? '').toString(),
      tripNotes: (m['trip_notes'] ?? '').toString(),
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
      pickupStops: rawPickupStops is List
          ? rawPickupStops
                .whereType<Map>()
                .map((e) => PickupTripStop.fromJson(e.cast<String, dynamic>()))
                .toList()
          : const [],
      rawFields: raw,
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
    required this.rawFields,
    this.failureReasonCode = '',
  });

  final int stop;
  final String externalDelivery;
  final String customer;
  final String address;
  final String mobile;
  final String status;
  final String deliveredAt;
  final String notes;
  final String failureReasonCode;
  final Map<String, dynamic> rawFields;

  String get failureReasonLabel => _reasonLabels[failureReasonCode] ?? failureReasonCode;

  static const Map<String, String> _reasonLabels = {
    'customer_unavailable': 'Customer Unavailable',
    'address_inaccessible': 'Address Inaccessible',
    'wrong_address': 'Wrong Address',
    'customer_refused_at_door': 'Customer Refused at Door',
    'damaged_in_transit': 'Damaged in Transit',
    'lost_in_transit': 'Lost in Transit',
    'suspected_fraud': 'Suspected Fraud',
  };

  factory ExternalDeliveryTripStop.fromJson(Map<String, dynamic> m) {
    final raw = Map<String, dynamic>.from(m);
    return ExternalDeliveryTripStop(
      stop: (m['stop'] as num?)?.toInt() ?? 0,
      externalDelivery: (m['external_delivery'] ?? '').toString(),
      customer: (m['customer'] ?? '').toString(),
      address: (m['address'] ?? '').toString(),
      mobile: (m['mobile'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      deliveredAt: (m['delivered_at'] ?? '').toString(),
      notes: (m['notes'] ?? '').toString(),
      failureReasonCode: (m['failure_reason_code'] ?? '').toString(),
      rawFields: raw,
    );
  }
}

class PickupTripStop {
  const PickupTripStop({
    required this.stop,
    required this.pickupJob,
    required this.customerName,
    required this.customerMobile,
    required this.pickupAddress,
    required this.status,
    this.failureReasonCode = '',
    this.rawFields = const {},
  });

  final int stop;
  final String pickupJob;
  final String customerName;
  final String customerMobile;
  final String pickupAddress;
  final String status;
  final String failureReasonCode;
  final Map<String, dynamic> rawFields;

  factory PickupTripStop.fromJson(Map<String, dynamic> m) {
    return PickupTripStop(
      stop: (m['stop'] as num?)?.toInt() ?? 0,
      pickupJob: (m['pickup_job'] ?? '').toString(),
      customerName: (m['customer_name'] ?? m['customer'] ?? '').toString(),
      customerMobile: (m['customer_mobile'] ?? m['mobile'] ?? '').toString(),
      pickupAddress: (m['pickup_address'] ?? m['address'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      failureReasonCode: (m['failure_reason_code'] ?? '').toString(),
      rawFields: m,
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
    'Failed' => const Color(0xFFC62828),
    'Return Initiated' => const Color(0xFF6A1B9A),
    'Returned' => const Color(0xFF4E342E),
    'Pending' => const Color(0xFF757575),
    _ => const Color(0xFF757575),
  };

  /// Brightness-aware variant of [statusColor]; the dark shades above are
  /// unreadable on dark surfaces, so dark mode uses lightened equivalents.
  Color statusColorIn(BuildContext context) {
    if (Theme.of(context).brightness != Brightness.dark) return statusColor;
    return switch (this) {
      'Delivered' => const Color(0xFF7BD980),
      'Added to Trip' => const Color(0xFFFFB059),
      'Failed' => const Color(0xFFFF8484),
      'Return Initiated' => const Color(0xFFC896F5),
      'Returned' => const Color(0xFFCDBBB5),
      'Pending' => const Color(0xFFB6BDCA),
      _ => const Color(0xFFB6BDCA),
    };
  }
}

