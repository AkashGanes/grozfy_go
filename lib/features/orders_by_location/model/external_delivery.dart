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
