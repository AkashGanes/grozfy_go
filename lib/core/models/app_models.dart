enum VerificationStatus { notSubmitted, pending, approved, rejected }

enum OrderProgressStatus {
  accepted,
  reachedPickup,
  pickedUp,
  outForDelivery,
  delivered,
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

class LoggedPartnerProfileDetails {
  const LoggedPartnerProfileDetails({
    this.loggedUser,
    this.employee,
    this.driver,
  });

  final String? loggedUser;
  final Map<String, dynamic>? employee;
  final Map<String, dynamic>? driver;

  bool get hasData => employee != null || driver != null;
}

class VehicleDetails {
  const VehicleDetails({
    this.name,
    required this.licensePlate,
    required this.make,
    required this.model,
    required this.lastOdometer,
    required this.fuelType,
    required this.uom,
    this.acquisitionDate,
    this.location,
    this.chassisNo,
    this.vehicleValue,
    this.employee,
    this.insuranceCompany,
    this.policyNo,
    this.startDate,
    this.endDate,
    this.carbonCheckDate,
    this.color,
    this.wheels,
    this.doors,
    this.status = VerificationStatus.approved,
  });

  final String? name;
  final String licensePlate;
  final String make;
  final String model;
  final int lastOdometer;
  final String fuelType;
  final String uom;
  final String? acquisitionDate;
  final String? location;
  final String? chassisNo;
  final double? vehicleValue;
  final String? employee;
  final String? insuranceCompany;
  final String? policyNo;
  final String? startDate;
  final String? endDate;
  final String? carbonCheckDate;
  final String? color;
  final int? wheels;
  final int? doors;
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
