import 'dart:convert';

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
    this.creation,
    this.modified,
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
  final String? creation;
  final String? modified;

  factory ExternalDeliveryDetail.fromJson(Map<String, dynamic> m) {
    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    // Try plain lat/lng fields first, then parse Frappe GeoJSON field
    double? lat = toDouble(m['latitude'] ?? m['delivery_latitude']);
    double? lng = toDouble(m['longitude'] ?? m['delivery_longitude']);

    if (lat == null || lng == null) {
      final coords = _parseGeoJson(
        m['geolocation'] ?? m['location'] ?? m['delivery_location'],
      );
      lat ??= coords?[0];
      lng ??= coords?[1];
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
      creation: _nullIfBlank(m['creation']?.toString()),
      modified: _nullIfBlank(m['modified']?.toString()),
    );
  }

  /// Parses Frappe's GeoJSON format:
  /// {"type":"FeatureCollection","features":[{"type":"Feature","geometry":
  ///   {"type":"Point","coordinates":[lng, lat]},...}]}
  /// Returns [lat, lng] or null.
  static List<double>? _parseGeoJson(dynamic raw) {
    if (raw == null) return null;
    try {
      final Map<String, dynamic> geo =
          raw is String ? jsonDecode(raw) as Map<String, dynamic> : raw as Map<String, dynamic>;

      // FeatureCollection
      if (geo['type'] == 'FeatureCollection') {
        final features = geo['features'] as List?;
        if (features == null || features.isEmpty) return null;
        final first = features.first as Map<String, dynamic>;
        return _pointFromGeometry(first['geometry'] as Map<String, dynamic>?);
      }
      // Feature
      if (geo['type'] == 'Feature') {
        return _pointFromGeometry(geo['geometry'] as Map<String, dynamic>?);
      }
      // Point directly
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
    return [lat, lng]; // return as [lat, lng]
  }

  static String? _nullIfBlank(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }
}
