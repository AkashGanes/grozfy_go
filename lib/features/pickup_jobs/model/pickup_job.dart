class PickupJobItem {
  const PickupJobItem({
    required this.itemName,
    required this.qty,
    this.itemCode,
    this.description,
    this.rate,
    this.amount,
  });

  final String itemName;
  final double qty;
  final String? itemCode;
  final String? description;
  final double? rate;
  final double? amount;

  factory PickupJobItem.fromJson(Map<String, dynamic> m) {
    double? toD(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return PickupJobItem(
      itemName: (m['item_name'] ?? m['item_code'] ?? '').toString(),
      qty: toD(m['qty']) ?? 1,
      itemCode: m['item_code']?.toString(),
      description: m['description']?.toString(),
      rate: toD(m['rate']),
      amount: toD(m['amount']),
    );
  }
}

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
    required this.docstatus,
    this.pickupLatitude,
    this.pickupLongitude,
    this.dropLatitude,
    this.dropLongitude,
    this.scheduledWindow,
    this.deliveryTrip,
    // Actual fields from getdoc
    this.returnRequest,
    this.storeUrl,
    this.storeId,
    this.deliveryNote,
    this.owner,
    this.modified,
    this.modifiedBy,
    // Optional extended fields (may appear on other statuses)
    this.customerEmail,
    this.storeName,
    this.notes,
    this.specialInstructions,
    this.proofPhoto,
    this.paymentMode,
    this.amount,
    this.codAmount,
    this.items = const [],
    this.rawData = const {},
  });

  final String name;
  final String sagaId;
  final String customerName;
  final String customerMobile;
  final String pickupAddress;
  final String dropAddress;
  final String creation;
  final String status;
  final int docstatus;

  final double? pickupLatitude;
  final double? pickupLongitude;
  final double? dropLatitude;
  final double? dropLongitude;
  final String? scheduledWindow;
  final String? deliveryTrip;

  // From actual API response
  final String? returnRequest;
  final String? storeUrl;
  final String? storeId;
  final String? deliveryNote;
  final String? owner;
  final String? modified;
  final String? modifiedBy;

  // May appear on later statuses
  final String? customerEmail;
  final String? storeName;
  final String? notes;
  final String? specialInstructions;
  final String? proofPhoto;
  final String? paymentMode;
  final double? amount;
  final double? codAmount;
  final List<PickupJobItem> items;
  /// Full raw document map from getdoc — used to display ALL fields dynamically.
  final Map<String, dynamic> rawData;

  factory PickupJob.fromJson(Map<String, dynamic> m) {
    double? toD(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    String? nullIfBlank(String? s) =>
        (s == null || s.trim().isEmpty) ? null : s.trim();

    final rawItems = m['items'];
    final items = <PickupJobItem>[];
    if (rawItems is List) {
      for (final row in rawItems) {
        if (row is Map<String, dynamic>) items.add(PickupJobItem.fromJson(row));
      }
    }

    return PickupJob(
      name: (m['name'] ?? '').toString(),
      sagaId: (m['saga_id'] ?? '').toString(),
      customerName: (m['customer_name'] ?? '').toString(),
      customerMobile:
          (m['customer_mobile'] ?? m['mobile_no'] ?? '').toString(),
      pickupAddress: (m['pickup_address'] ?? '').toString(),
      dropAddress:
          (m['drop_address'] ?? m['store_address'] ?? '').toString(),
      creation: (m['creation'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      docstatus: int.tryParse(m['docstatus']?.toString() ?? '0') ?? 0,
      pickupLatitude: toD(m['pickup_latitude']),
      pickupLongitude: toD(m['pickup_longitude']),
      dropLatitude: toD(m['drop_latitude']),
      dropLongitude: toD(m['drop_longitude']),
      scheduledWindow: nullIfBlank(m['scheduled_window']?.toString()),
      deliveryTrip: nullIfBlank(m['delivery_trip']?.toString()),
      returnRequest: nullIfBlank(m['return_request']?.toString()),
      storeUrl: nullIfBlank(m['store_url']?.toString()),
      storeId: nullIfBlank(m['store_id']?.toString()),
      deliveryNote: nullIfBlank(m['delivery_note']?.toString()),
      owner: nullIfBlank(m['owner']?.toString()),
      modified: nullIfBlank(m['modified']?.toString()),
      modifiedBy: nullIfBlank(m['modified_by']?.toString()),
      customerEmail: nullIfBlank(m['customer_email']?.toString()),
      storeName: nullIfBlank(m['store_name']?.toString()),
      notes: nullIfBlank(
        m['notes']?.toString() ??
            m['pickup_notes']?.toString() ??
            m['driver_notes']?.toString(),
      ),
      specialInstructions:
          nullIfBlank(m['special_instructions']?.toString()),
      proofPhoto: nullIfBlank(m['proof_photo']?.toString()),
      paymentMode: nullIfBlank(
        m['payment_mode']?.toString() ?? m['payment_method']?.toString(),
      ),
      amount: toD(m['amount'] ?? m['refund_amount'] ?? m['grand_total']),
      codAmount: toD(m['cod_amount']),
      items: items,
      rawData: Map<String, dynamic>.from(m),
    );
  }

  /// Returns true when the lat/lng are both set and non-zero.
  bool get hasPickupCoords =>
      pickupLatitude != null &&
      pickupLongitude != null &&
      (pickupLatitude! != 0.0 || pickupLongitude! != 0.0);

  bool get hasDropCoords =>
      dropLatitude != null &&
      dropLongitude != null &&
      (dropLatitude! != 0.0 || dropLongitude! != 0.0);
}
