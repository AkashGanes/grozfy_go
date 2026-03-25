// ignore_for_file: constant_identifier_names

enum VerificationStatus { notSubmitted, pending, approved, rejected }

enum VehicleType { bike, car, cycle }

enum OrderProgressStatus {
  accepted,
  reachedPickup,
  pickedUp,
  outForDelivery,
  delivered,
}

enum AuthMode { otp, password }

enum ExternalDeliveryStatus {
  Pending,
  Accepted,
  PickedUp,
  OutForDelivery,
  Delivered,
  Cancelled,
}

extension ExternalDeliveryStatusExtension on ExternalDeliveryStatus {
  String get label {
    switch (this) {
      case ExternalDeliveryStatus.Pending:
        return 'Pending';
      case ExternalDeliveryStatus.Accepted:
        return 'Accepted';
      case ExternalDeliveryStatus.PickedUp:
        return 'Picked Up';
      case ExternalDeliveryStatus.OutForDelivery:
        return 'Out for Delivery';
      case ExternalDeliveryStatus.Delivered:
        return 'Delivered';
      case ExternalDeliveryStatus.Cancelled:
        return 'Cancelled';
    }
  }
}

class ExternalDeliveryOrder {
  ExternalDeliveryOrder({
    required this.name,
    required this.storeName,
    required this.storeUrl,
    required this.customerName,
    required this.status,
    this.pickupLat,
    this.pickupLng,
    this.dropLat,
    this.dropLng,
    this.pickupAddress,
    this.dropAddress,
    this.contactNumber,
    this.creation,
    this.modified,
  });

  final String name;
  final String storeName;
  final String storeUrl;
  final String customerName;
  final String status;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropLat;
  final double? dropLng;
  final String? pickupAddress;
  final String? dropAddress;
  final String? contactNumber;
  final DateTime? creation;
  final DateTime? modified;

  factory ExternalDeliveryOrder.fromJson(Map<String, dynamic> json) {
    return ExternalDeliveryOrder(
      name: json['name'] ?? '',
      storeName: json['store_name'] ?? 'Unknown Store',
      storeUrl: json['store_url'] ?? '',
      customerName: json['customer_name'] ?? 'Unknown Customer',
      status: json['status'] ?? 'Pending',
      pickupLat: _parseDouble(json['pickup_lat']),
      pickupLng: _parseDouble(json['pickup_lng']),
      dropLat: _parseDouble(json['drop_lat']),
      dropLng: _parseDouble(json['drop_lng']),
      pickupAddress: json['pickup_address'],
      dropAddress: json['drop_address'],
      contactNumber: json['contact_number'] ?? json['customer_phone'],
      creation: json['creation'] != null
          ? DateTime.tryParse(json['creation'].toString())
          : null,
      modified: json['modified'] != null
          ? DateTime.tryParse(json['modified'].toString())
          : null,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool get hasPickupLocation => pickupLat != null && pickupLng != null;
  bool get hasDropLocation => dropLat != null && dropLng != null;

  ExternalDeliveryStatus get deliveryStatus {
    switch (status.toLowerCase()) {
      case 'pending':
        return ExternalDeliveryStatus.Pending;
      case 'accepted':
        return ExternalDeliveryStatus.Accepted;
      case 'picked up':
      case 'pickedup':
        return ExternalDeliveryStatus.PickedUp;
      case 'out for delivery':
      case 'outfordelivery':
        return ExternalDeliveryStatus.OutForDelivery;
      case 'delivered':
        return ExternalDeliveryStatus.Delivered;
      case 'cancelled':
        return ExternalDeliveryStatus.Cancelled;
      default:
        return ExternalDeliveryStatus.Pending;
    }
  }
}

class PartnerProfile {
  const PartnerProfile({
    required this.fullName,
    required this.mobile,
    this.email,
    this.referralCode,
  });

  final String fullName;
  final String mobile;
  final String? email;
  final String? referralCode;

  PartnerProfile copyWith({
    String? fullName,
    String? mobile,
    String? email,
    String? referralCode,
  }) {
    return PartnerProfile(
      fullName: fullName ?? this.fullName,
      mobile: mobile ?? this.mobile,
      email: email ?? this.email,
      referralCode: referralCode ?? this.referralCode,
    );
  }
}

class VehicleDetails {
  const VehicleDetails({
    required this.type,
    required this.vehicleNumber,
    required this.rcUploaded,
    this.status = VerificationStatus.pending,
  });

  final VehicleType type;
  final String vehicleNumber;
  final bool rcUploaded;
  final VerificationStatus status;
}

class BankDetails {
  const BankDetails({
    required this.accountNumber,
    required this.ifsc,
    required this.accountHolder,
    this.upiId,
    this.verified = false,
  });

  final String accountNumber;
  final String ifsc;
  final String accountHolder;
  final String? upiId;
  final bool verified;
}

class EarningsSummary {
  const EarningsSummary({
    required this.today,
    required this.week,
    required this.total,
    required this.pendingPayout,
  });

  final double today;
  final double week;
  final double total;
  final double pendingPayout;

  EarningsSummary copyWith({
    double? today,
    double? week,
    double? total,
    double? pendingPayout,
  }) {
    return EarningsSummary(
      today: today ?? this.today,
      week: week ?? this.week,
      total: total ?? this.total,
      pendingPayout: pendingPayout ?? this.pendingPayout,
    );
  }
}

class PerformanceMetrics {
  const PerformanceMetrics({
    required this.rating,
    required this.acceptanceRate,
    required this.completionRate,
    required this.totalDeliveries,
  });

  final double rating;
  final double acceptanceRate;
  final double completionRate;
  final int totalDeliveries;

  PerformanceMetrics copyWith({
    double? rating,
    double? acceptanceRate,
    double? completionRate,
    int? totalDeliveries,
  }) {
    return PerformanceMetrics(
      rating: rating ?? this.rating,
      acceptanceRate: acceptanceRate ?? this.acceptanceRate,
      completionRate: completionRate ?? this.completionRate,
      totalDeliveries: totalDeliveries ?? this.totalDeliveries,
    );
  }
}

class AppNotice {
  const AppNotice({
    required this.title,
    required this.message,
    required this.time,
  });

  final String title;
  final String message;
  final DateTime time;
}

class DeliveryOrder {
  const DeliveryOrder({
    required this.id,
    required this.customerName,
    required this.storeName,
    required this.contactNumber,
    required this.pickup,
    required this.drop,
    required this.deliveryInstructions,
    required this.paymentMode,
    required this.distanceKm,
    required this.estimatedEarnings,
    this.status = OrderProgressStatus.accepted,
  });

  final String id;
  final String customerName;
  final String storeName;
  final String contactNumber;
  final String pickup;
  final String drop;
  final String deliveryInstructions;
  final String paymentMode;
  final double distanceKm;
  final double estimatedEarnings;
  final OrderProgressStatus status;

  DeliveryOrder copyWith({OrderProgressStatus? status}) {
    return DeliveryOrder(
      id: id,
      customerName: customerName,
      storeName: storeName,
      contactNumber: contactNumber,
      pickup: pickup,
      drop: drop,
      deliveryInstructions: deliveryInstructions,
      paymentMode: paymentMode,
      distanceKm: distanceKm,
      estimatedEarnings: estimatedEarnings,
      status: status ?? this.status,
    );
  }
}

class PermissionState {
  const PermissionState({
    this.foregroundLocation = false,
    this.backgroundLocation = false,
    this.notification = false,
  });

  final bool foregroundLocation;
  final bool backgroundLocation;
  final bool notification;

  bool get allGranted =>
      foregroundLocation && backgroundLocation && notification;

  PermissionState copyWith({
    bool? foregroundLocation,
    bool? backgroundLocation,
    bool? notification,
  }) {
    return PermissionState(
      foregroundLocation: foregroundLocation ?? this.foregroundLocation,
      backgroundLocation: backgroundLocation ?? this.backgroundLocation,
      notification: notification ?? this.notification,
    );
  }
}

extension VerificationStatusLabel on VerificationStatus {
  String get label {
    switch (this) {
      case VerificationStatus.notSubmitted:
        return 'Not Submitted';
      case VerificationStatus.pending:
        return 'Pending';
      case VerificationStatus.approved:
        return 'Approved';
      case VerificationStatus.rejected:
        return 'Rejected';
    }
  }
}

extension VehicleTypeLabel on VehicleType {
  String get label {
    switch (this) {
      case VehicleType.bike:
        return 'Bike';
      case VehicleType.car:
        return 'Car';
      case VehicleType.cycle:
        return 'Cycle';
    }
  }
}

extension OrderStatusLabel on OrderProgressStatus {
  String get label {
    switch (this) {
      case OrderProgressStatus.accepted:
        return 'Accepted';
      case OrderProgressStatus.reachedPickup:
        return 'Reached Pickup';
      case OrderProgressStatus.pickedUp:
        return 'Picked Up';
      case OrderProgressStatus.outForDelivery:
        return 'Out for Delivery';
      case OrderProgressStatus.delivered:
        return 'Delivered';
    }
  }
}
