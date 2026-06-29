import 'dart:convert';

class DeliveryItem {
  const DeliveryItem({
    required this.itemName,
    required this.qty,
    this.rate,
    this.amount,
  });

  final String itemName;
  final double qty;
  final double? rate;
  final double? amount;

  factory DeliveryItem.fromJson(Map<String, dynamic> m) {
    double? toD(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return DeliveryItem(
      itemName: (m['item_name'] ?? m['item_code'] ?? '').toString(),
      qty: toD(m['qty'] ?? m['quantity']) ?? 1,
      rate: toD(m['rate']),
      amount: toD(m['amount']),
    );
  }
}

class ExternalDeliveryDetail {
  const ExternalDeliveryDetail({
    required this.name,
    required this.storeName,
    required this.storeUrl,
    required this.customerName,
    required this.status,
    this.contactMobile,
    this.deliveryAddress,
    this.pickupAddress,
    this.latitude,
    this.longitude,
    this.paymentMode,
    this.paymentMethod,
    this.grandTotal,
    this.codAmountToCollect,
    this.items = const [],
    this.creation,
    this.modified,
    this.proofPhoto,
    this.failureReasonCode = '',
    this.deliveryNotes = '',
  });

  final String name;
  final String storeName;
  final String storeUrl;
  final String customerName;
  final String status;
  final String? contactMobile;
  final String? deliveryAddress;
  final String? pickupAddress;
  final double? latitude;
  final double? longitude;
  final String? paymentMode;
  final String? paymentMethod;
  final double? grandTotal;
  final double? codAmountToCollect;
  final List<DeliveryItem> items;
  final String? creation;
  final String? modified;
  final String? proofPhoto;
  final String failureReasonCode;
  final String deliveryNotes;

  bool get isCod =>
      paymentMethod?.toUpperCase() == 'COD' ||
      paymentMode?.toUpperCase() == 'COD';

  static const Map<String, String> _reasonLabels = {
    'customer_unavailable': 'Customer Unavailable',
    'address_inaccessible': 'Address Inaccessible',
    'wrong_address': 'Wrong Address',
    'customer_refused_at_door': 'Customer Refused at Door',
    'damaged_in_transit': 'Damaged in Transit',
    'lost_in_transit': 'Lost in Transit',
    'suspected_fraud': 'Suspected Fraud',
  };

  String get failureReasonLabel =>
      _reasonLabels[failureReasonCode] ?? failureReasonCode;

  factory ExternalDeliveryDetail.fromJson(Map<String, dynamic> m) {
    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    // Coordinates
    double? lat = toDouble(m['latitude'] ?? m['delivery_latitude']);
    double? lng = toDouble(m['longitude'] ?? m['delivery_longitude']);

    if (lat == null || lng == null) {
      final coords = _parseGeoJson(
        m['geolocation'] ?? m['location'] ?? m['delivery_location'],
      );
      lat ??= coords?[0];
      lng ??= coords?[1];
    }

    // Items child table
    final rawItems = m['items'];
    final items = <DeliveryItem>[];
    if (rawItems is List) {
      for (final row in rawItems) {
        if (row is Map<String, dynamic>) {
          items.add(DeliveryItem.fromJson(row));
        }
      }
    }

    return ExternalDeliveryDetail(
      name: (m['name'] ?? '').toString(),
      storeName: (m['store_name'] ?? '').toString(),
      storeUrl: (m['store_url'] ?? '').toString(),
      customerName: (m['customer_name'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      contactMobile: _nullIfBlank(m['contact_mobile']?.toString())
          ?? _nullIfBlank(m['customer_mobile']?.toString())
          ?? _nullIfBlank(m['mobile_no']?.toString()),
      deliveryAddress: _nullIfBlank(m['delivery_address']?.toString())
          ?? _nullIfBlank(m['address']?.toString()),
      pickupAddress: _nullIfBlank(m['pickup_address']?.toString())
          ?? _nullIfBlank(m['store_address']?.toString()),
      latitude: lat,
      longitude: lng,
      paymentMode: _nullIfBlank(
        m['payment_mode']?.toString() ??
        m['mode_of_payment']?.toString() ??
        m['payment_method']?.toString(),
      ),
      paymentMethod: _nullIfBlank(m['payment_method']?.toString()),
      grandTotal: toDouble(m['grand_total'] ?? m['total'] ?? m['amount']),
      codAmountToCollect: toDouble(m['cod_amount_to_collect']),
      items: items,
      creation: _nullIfBlank(m['creation']?.toString()),
      modified: _nullIfBlank(m['modified']?.toString()),
      proofPhoto: _nullIfBlank(m['proof_photo']?.toString()),
      failureReasonCode: (m['failure_reason_code'] ?? '').toString(),
      deliveryNotes: (m['delivery_notes'] ?? '').toString(),
    );
  }

  static List<double>? _parseGeoJson(dynamic raw) {
    if (raw == null) return null;
    try {
      final Map<String, dynamic> geo = raw is String
          ? jsonDecode(raw) as Map<String, dynamic>
          : raw as Map<String, dynamic>;

      if (geo['type'] == 'FeatureCollection') {
        final features = geo['features'] as List?;
        if (features == null || features.isEmpty) return null;
        final first = features.first as Map<String, dynamic>;
        return _pointFromGeometry(first['geometry'] as Map<String, dynamic>?);
      }
      if (geo['type'] == 'Feature') {
        return _pointFromGeometry(geo['geometry'] as Map<String, dynamic>?);
      }
      if (geo['type'] == 'Point') {
        return _pointFromGeometry(geo);
      }
    } catch (_) {}
    return null;
  }

  static List<double>? _pointFromGeometry(Map<String, dynamic>? geo) {
    if (geo == null || geo['type'] != 'Point') return null;
    final coords = geo['coordinates'] as List?;
    if (coords == null || coords.length < 2) return null;
    final lng = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();
    return [lat, lng];
  }

  static String? _nullIfBlank(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }
}
