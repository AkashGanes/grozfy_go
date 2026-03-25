enum VerificationStatus { notSubmitted, pending, approved, rejected }

enum VehicleType { bike, car, cycle }

enum OrderStatus {
  pending,
  accepted,
  rejected,
  reachedPickup,
  pickedUp,
  outForDelivery,
  delivered,
  cancelled,
}

typedef OrderProgressStatus = OrderStatus;

enum OrderAssignmentStatus { unassigned, assigned }

enum AuthMode { otp, password }

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

class OrderItem {
  const OrderItem({
    required this.name,
    required this.quantity,
    required this.price,
  });

  final String name;
  final int quantity;
  final double price;

  OrderItem copyWith({String? name, int? quantity, double? price}) {
    return OrderItem(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
    );
  }
}

class GeoLocation {
  const GeoLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  GeoLocation copyWith({double? latitude, double? longitude}) {
    return GeoLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  String get coordinateString =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

class DeliveryOrder {
  const DeliveryOrder({
    required this.orderId,
    required this.customerName,
    required this.customerPhone,
    required this.deliveryAddress,
    required this.storeId,
    required this.storeName,
    required this.storeContact,
    required this.storeAddress,
    required this.orderItems,
    required this.orderStatus,
    required this.latitude,
    required this.longitude,
    this.id = '',
    this.contactNumber = '',
    this.pickup = '',
    this.drop = '',
    this.deliveryInstructions = '',
    this.paymentMode = '',
    this.distanceKm = 0,
    this.estimatedEarnings = 0,
    this.assignmentStatus = OrderAssignmentStatus.unassigned,
    this.assignedDeliveryPartnerId,
    this.reachedStoreAt,
    this.deliveryPartnerLocation,
  });

  final String id;
  final String orderId;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final String storeId;
  final String storeName;
  final String storeContact;
  final String storeAddress;
  final List<OrderItem> orderItems;
  final OrderStatus orderStatus;
  final double latitude;
  final double longitude;
  final String contactNumber;
  final String pickup;
  final String drop;
  final String deliveryInstructions;
  final String paymentMode;
  final double distanceKm;
  final double estimatedEarnings;
  final OrderAssignmentStatus assignmentStatus;
  final String? assignedDeliveryPartnerId;
  final DateTime? reachedStoreAt;
  final GeoLocation? deliveryPartnerLocation;

  double get totalAmount =>
      orderItems.fold(0, (sum, item) => sum + (item.price * item.quantity));

  DeliveryOrder copyWith({
    String? id,
    String? orderId,
    String? customerName,
    String? customerPhone,
    String? deliveryAddress,
    String? storeId,
    String? storeName,
    String? storeContact,
    String? storeAddress,
    List<OrderItem>? orderItems,
    OrderStatus? orderStatus,
    double? latitude,
    double? longitude,
    String? contactNumber,
    String? pickup,
    String? drop,
    String? deliveryInstructions,
    String? paymentMode,
    double? distanceKm,
    double? estimatedEarnings,
    OrderAssignmentStatus? assignmentStatus,
    String? assignedDeliveryPartnerId,
    DateTime? reachedStoreAt,
    GeoLocation? deliveryPartnerLocation,
  }) {
    return DeliveryOrder(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      storeId: storeId ?? this.storeId,
      storeName: storeName ?? this.storeName,
      storeContact: storeContact ?? this.storeContact,
      storeAddress: storeAddress ?? this.storeAddress,
      orderItems: orderItems ?? this.orderItems,
      orderStatus: orderStatus ?? this.orderStatus,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      contactNumber: contactNumber ?? this.contactNumber,
      pickup: pickup ?? this.pickup,
      drop: drop ?? this.drop,
      deliveryInstructions: deliveryInstructions ?? this.deliveryInstructions,
      paymentMode: paymentMode ?? this.paymentMode,
      distanceKm: distanceKm ?? this.distanceKm,
      estimatedEarnings: estimatedEarnings ?? this.estimatedEarnings,
      assignmentStatus: assignmentStatus ?? this.assignmentStatus,
      assignedDeliveryPartnerId:
          assignedDeliveryPartnerId ?? this.assignedDeliveryPartnerId,
      reachedStoreAt: reachedStoreAt ?? this.reachedStoreAt,
      deliveryPartnerLocation:
          deliveryPartnerLocation ?? this.deliveryPartnerLocation,
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
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.accepted:
        return 'Accepted';
      case OrderStatus.rejected:
        return 'Rejected';
      case OrderStatus.reachedPickup:
        return 'Reached Pickup';
      case OrderStatus.pickedUp:
        return 'Picked Up';
      case OrderStatus.outForDelivery:
        return 'Out for Delivery';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }
}
