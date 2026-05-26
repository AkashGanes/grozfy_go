class PickupJob {
  const PickupJob({
    required this.name,
    required this.sagaId,
    required this.customerName,
    required this.customerMobile,
    required this.pickupAddress,
    required this.dropAddress,
    required this.creation,
    required this.status,
    this.pickupLatitude,
    this.pickupLongitude,
    this.dropLatitude,
    this.dropLongitude,
    this.scheduledWindow,
  });

  final String name;
  final String sagaId;
  final String customerName;
  final String customerMobile;
  final String pickupAddress;
  final String dropAddress;
  final String creation;
  final String status;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final double? dropLatitude;
  final double? dropLongitude;
  final String? scheduledWindow;

  factory PickupJob.fromJson(Map<String, dynamic> m) {
    double? toD(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return PickupJob(
      name: (m['name'] ?? '').toString(),
      sagaId: (m['saga_id'] ?? '').toString(),
      customerName: (m['customer_name'] ?? '').toString(),
      customerMobile: (m['customer_mobile'] ?? '').toString(),
      pickupAddress: (m['pickup_address'] ?? '').toString(),
      dropAddress: (m['drop_address'] ?? '').toString(),
      creation: (m['creation'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      pickupLatitude: toD(m['pickup_latitude']),
      pickupLongitude: toD(m['pickup_longitude']),
      dropLatitude: toD(m['drop_latitude']),
      dropLongitude: toD(m['drop_longitude']),
      scheduledWindow: m['scheduled_window']?.toString(),
    );
  }
}
