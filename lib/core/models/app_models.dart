// ignore_for_file: constant_identifier_names
import '../localization/app_strings.dart';
import '../utils/html_utils.dart';

enum VerificationStatus { notSubmitted, pending, approved, rejected }

enum OrderStatus {
  pending,
  accepted,
  rejected,
  reachedPickup,
  pickedUp,
  outForDelivery,
  delivered,
  failed,
  cancelled,
  returned,
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

class VehicleSubmitResult {
  const VehicleSubmitResult({
    this.error,
    this.vehicleName,
    this.vehicleData,
    this.wasUpdate = false,
  });

  final String? error;
  final String? vehicleName;
  final Map<String, dynamic>? vehicleData;
  final bool wasUpdate;

  bool get success => error == null;
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
    this.customerEmail = '',
    this.pickup = '',
    this.drop = '',
    this.deliveryInstructions = '',
    this.paymentMode = '',
    this.distanceKm = 0,
    this.estimatedEarnings = 0,
    this.assignmentStatus = OrderAssignmentStatus.unassigned,
    this.assignedDeliveryPartnerId,
    this.reachedStoreAt,
    this.acceptedAt,
    this.completedAt,
    this.deliveryPartnerLocation,
    this.createdAt,
    this.failureReasonCode = '',
    this.deliveryNotes = '',
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
  final String customerEmail;
  final String pickup;
  final String drop;
  final String deliveryInstructions;
  final String paymentMode;
  final double distanceKm;
  final double estimatedEarnings;
  final OrderAssignmentStatus assignmentStatus;
  final String? assignedDeliveryPartnerId;
  final DateTime? reachedStoreAt;
  final DateTime? acceptedAt;
  final DateTime? completedAt;
  final GeoLocation? deliveryPartnerLocation;
  final DateTime? createdAt;
  final String failureReasonCode;
  final String deliveryNotes;

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
    String? customerEmail,
    String? pickup,
    String? drop,
    String? deliveryInstructions,
    String? paymentMode,
    double? distanceKm,
    double? estimatedEarnings,
    OrderAssignmentStatus? assignmentStatus,
    String? assignedDeliveryPartnerId,
    DateTime? reachedStoreAt,
    DateTime? acceptedAt,
    DateTime? completedAt,
    GeoLocation? deliveryPartnerLocation,
    DateTime? createdAt,
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
      customerEmail: customerEmail ?? this.customerEmail,
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
      acceptedAt: acceptedAt ?? this.acceptedAt,
      completedAt: completedAt ?? this.completedAt,
      deliveryPartnerLocation:
          deliveryPartnerLocation ?? this.deliveryPartnerLocation,
      createdAt: createdAt ?? this.createdAt,
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
  String get localizationKey {
    switch (this) {
      case VerificationStatus.notSubmitted:
        return 'not_submitted';
      case VerificationStatus.pending:
        return 'pending';
      case VerificationStatus.approved:
        return 'approved';
      case VerificationStatus.rejected:
        return 'rejected';
    }
  }

  String get label {
    return AppStrings.get('en', localizationKey);
  }

  String localizedLabel(String languageCode) {
    return AppStrings.get(languageCode, localizationKey);
  }
}

extension OrderStatusLabel on OrderProgressStatus {
  String get localizationKey {
    switch (this) {
      case OrderStatus.pending:
        return 'pending';
      case OrderStatus.accepted:
        return 'accepted';
      case OrderStatus.rejected:
        return 'rejected';
      case OrderStatus.reachedPickup:
        return 'reached_pickup';
      case OrderStatus.pickedUp:
        return 'picked_up';
      case OrderStatus.outForDelivery:
        return 'out_for_delivery';
      case OrderStatus.delivered:
        return 'delivered';
      case OrderStatus.failed:
        return 'failed';
      case OrderStatus.cancelled:
        return 'cancelled';
      case OrderStatus.returned:
        return 'returned';
    }
  }

  String get label {
    return AppStrings.get('en', localizationKey);
  }

  String localizedLabel(String languageCode) {
    return AppStrings.get(languageCode, localizationKey);
  }
}

class ProfileCompletenessItem {
  const ProfileCompletenessItem({
    required this.name,
    required this.description,
    required this.isCompleted,
    this.route,
  });

  final String name;
  final String description;
  final bool isCompleted;
  final String? route;
}

class ProfileCompleteness {
  const ProfileCompleteness({
    required this.percentage,
    required this.items,
    required this.completedCount,
    required this.totalCount,
  });

  final double percentage;
  final List<ProfileCompletenessItem> items;
  final int completedCount;
  final int totalCount;

  String get messageKey {
    if (percentage >= 1) {
      return 'profile_complete_message';
    } else if (percentage >= 0.7) {
      return 'profile_almost_complete_message';
    } else if (percentage >= 0.4) {
      return 'profile_progress_message';
    } else {
      return 'profile_incomplete_message';
    }
  }

  String get message {
    return AppStrings.get('en', messageKey)
        .replaceAll('{completed}', '$completedCount')
        .replaceAll('{total}', '$totalCount');
  }

  String localizedMessage(String languageCode) {
    return AppStrings.get(languageCode, messageKey)
        .replaceAll('{completed}', '$completedCount')
        .replaceAll('{total}', '$totalCount');
  }

  ProfileCompletenessItem? get nextIncompleteItem {
    for (final item in items) {
      if (!item.isCompleted) {
        return item;
      }
    }
    return null;
  }
}

class NotificationLog {
  const NotificationLog({
    required this.name,
    required this.subject,
    required this.message,
    this.type,
    this.refDoctype,
    this.refName,
    this.read = false,
    this.creation,
  });

  final String name;
  final String subject;
  final String message;
  final String? type;
  final String? refDoctype;
  final String? refName;
  final bool read;
  final DateTime? creation;

  static bool _parseReadFlag(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value.toInt() == 1;
    final String normalized = value.toString().trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  factory NotificationLog.fromJson(Map<String, dynamic> json) {
    return NotificationLog(
      name: (json['name'] ?? '').toString().trim(),
      subject: HtmlUtils.stripHtml((json['subject'] ?? '').toString()),
      // Map email_content (ERPNext field) to message
      message: HtmlUtils.stripHtmlPreserveLineBreaks(
        (json['message'] ?? json['email_content'] ?? '').toString(),
      ),
      type: json['type'],
      // Map document_type to refDoctype if ref_doctype is missing
      refDoctype: json['ref_doctype'] ?? json['document_type'],
      // Map document_name to refName if ref_name is missing
      refName: json['ref_name'] ?? json['document_name'],
      read: _parseReadFlag(json['read']),
      creation: json['creation'] != null
          ? DateTime.tryParse(json['creation'].toString())
          : null,
    );
  }

  factory NotificationLog.fromBroadcastJson(
    Map<String, dynamic> json, {
    required bool read,
  }) {
    return NotificationLog(
      name: (json['name'] ?? '').toString(),
      subject: HtmlUtils.stripHtml(
        (json['title'] ?? json['subject'] ?? '').toString(),
      ),
      message: HtmlUtils.stripHtmlPreserveLineBreaks(
        (json['message'] ?? json['body'] ?? json['email_content'] ?? '')
            .toString(),
      ),
      type: (json['type'] ?? 'Alert').toString(),
      refDoctype:
          (json['doctype_ref'] ?? json['ref_doctype'] ?? json['document_type'])
              ?.toString(),
      refName:
          (json['docname_ref'] ?? json['ref_name'] ?? json['document_name'])
              ?.toString(),
      read: read,
      creation: json['creation'] != null
          ? DateTime.tryParse(json['creation'].toString())
          : null,
    );
  }
}

/// One reason a deletion request could not proceed — cash still held, a trip
/// still open, a legal hold. The backend sends `message` already worded and
/// localised, so the app never builds a sentence from `code`.
///
/// Spec: docs/backend-specs/request_account_deletion.md §7.
class AccountDeletionBlocker {
  const AccountDeletionBlocker({
    required this.code,
    required this.message,
    this.amount,
    this.count,
  });

  final String code;
  final String message;
  final double? amount;
  final int? count;

  factory AccountDeletionBlocker.fromJson(Map<String, dynamic> json) {
    return AccountDeletionBlocker(
      code: (json['code'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      amount: json['amount'] == null
          ? null
          : double.tryParse(json['amount'].toString()),
      count: json['count'] == null
          ? null
          : int.tryParse(json['count'].toString()),
    );
  }
}

/// State of the partner's account deletion request.
///
/// [status] is the outcome of the call — `none`, `success`, `blocked`,
/// `already_requested`, `cancelled` — while [requestStatus] is the lifecycle
/// state of the row itself (`Requested`, `Blocked`, `Approved`, `Cancelled`,
/// `Rejected`, `Completed`). They answer different questions: the first says
/// what just happened, the second what is true now.
class AccountDeletionStatus {
  const AccountDeletionStatus({
    required this.status,
    this.requestName,
    this.requestStatus,
    this.requestedOn,
    this.scheduledDeletionOn,
    this.cancellableUntil,
    this.blockers = const <AccountDeletionBlocker>[],
  });

  final String status;
  final String? requestName;
  final String? requestStatus;
  final DateTime? requestedOn;
  final DateTime? scheduledDeletionOn;
  final DateTime? cancellableUntil;
  final List<AccountDeletionBlocker> blockers;

  static const AccountDeletionStatus none =
      AccountDeletionStatus(status: 'none');

  /// A request exists and has not reached a terminal state.
  bool get isPending =>
      requestStatus == 'Requested' ||
      requestStatus == 'Blocked' ||
      requestStatus == 'Approved';

  /// Settlement is outstanding — [blockers] says what to clear.
  bool get isBlocked => status == 'blocked' || requestStatus == 'Blocked';

  /// Scheduled and inside the grace period, so it can still be called off.
  bool get isCancellable =>
      requestStatus == 'Approved' && requestName != null;

  factory AccountDeletionStatus.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String key) {
      final Object? raw = json[key];
      if (raw == null || raw.toString().trim().isEmpty) return null;
      return DateTime.tryParse(raw.toString());
    }

    final Object? rawBlockers = json['blockers'];
    return AccountDeletionStatus(
      status: (json['status'] ?? 'none').toString(),
      requestName: json['request_name']?.toString(),
      requestStatus: json['request_status']?.toString(),
      requestedOn: parse('requested_on'),
      scheduledDeletionOn: parse('scheduled_deletion_on'),
      cancellableUntil: parse('cancellable_until'),
      blockers: rawBlockers is List
          ? rawBlockers
                .whereType<Map<String, dynamic>>()
                .map(AccountDeletionBlocker.fromJson)
                .where((b) => b.message.isNotEmpty)
                .toList(growable: false)
          : const <AccountDeletionBlocker>[],
    );
  }
}
