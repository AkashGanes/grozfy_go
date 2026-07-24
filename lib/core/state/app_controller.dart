import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants/api_constants.dart';
import '../localization/app_strings.dart';
import '../localization/localized_text.dart';
import '../models/app_models.dart';
import '../navigation/app_routes.dart';
import '../services/connectivity_service.dart';
import '../services/timing_sync_engine.dart';
import '../services/fcm_initializer.dart';
import '../services/fcm_service.dart';
import '../services/location_ping_service.dart';
import '../services/secure_token_storage.dart';
import '../services/sync_manager.dart';
import '../utils/formatters.dart';
import '../utils/validators.dart' as app_validators;
import '../../features/orders_by_location/model/external_delivery.dart';
import '../../features/orders_by_location/model/external_delivery_detail.dart';
import '../../features/orders_by_location/repository/external_delivery_repository.dart';
import '../database/app_database.dart';
import '../database/partner_timing_log_dao.dart';
import '../widgets/partner_widget_manager.dart';

class AppController extends ChangeNotifier {
  static const Duration _networkTimeout = Duration(seconds: 15);
  static const String _storeId = 'STORE-25-0259';
  static final Uri _sendOtpUri = Uri.parse(
    'http://209.182.232.35:8004/api/method/frappe.core.api.billing_auth_v4.send_whatsapp_otp',
  );
  static final Uri _verifyOtpUri = Uri.parse(
    'http://209.182.232.35:8004/api/method/frappe.core.api.billing_auth_v4.verify_whatsapp_otp',
  );
  static final Uri _registerPartnerUri = Uri.parse(
    'http://209.182.232.35:8004/api/method/frappe.core.api.billing_auth_v4.register_delivery_partner',
  );
  static final Uri _submitDriverKycUri = Uri.parse(
    'http://209.182.232.35:8004/api/method/frappe.core.api.billing_auth_v4.submit_driver_kyc',
  );
  static final Uri _uploadFileUri = Uri.parse(
    'http://209.182.232.35:8004/api/method/frappe.core.api.billing_auth_v4.upload_kyc_file',
  );
  static final Uri _refreshTokenUri = Uri.parse(
    'http://209.182.232.35:8004/api/method/frappe.integrations.oauth2.get_token',
  );
  static final Uri _revokeTokenUri = Uri.parse(
    'http://209.182.232.35:8004/api/method/frappe.integrations.oauth2.revoke_token',
  );
  static final Uri _serverLogoutUri = Uri.parse(
    'http://209.182.232.35:8004/api/method/logout',
  );
  static const String _prefLanguageCode = 'language_code';
  static const String _prefMobile = 'partner_mobile';
  static const String _prefEmail = 'partner_email';
  static const String _prefFullName = 'partner_full_name';
  static const String _prefProfileImagePath = 'partner_profile_image_path';
  static const String _prefServerProfileImageUrl = 'server_profile_image_url';
  static const String _prefRememberMe = 'remember_me';
  static const String _prefCurrentLat = 'current_lat';
  static const String _prefCurrentLng = 'current_lng';
  static const String _prefCurrentLocationLabel = 'current_location_label';
  static const String _prefSelectedStore = 'selected_store_name';
  static const String _prefActiveOrdersCache = 'active_orders_cache';
  static const String _prefProfileCompleted = 'profile_completed';
  static const String _prefDriverName = 'driver_name';
  static const String _prefKycCompleted = 'kyc_completed';
  static const String _prefKycLicenseNo = 'kyc_license_no';
  static const String _prefKycAadharNo = 'kyc_aadhar_no';
  static const String _prefKycPanNo = 'kyc_pan_no';
  static const String _prefKycLicenseUrl = 'kyc_license_url';
  static const String _prefKycAadharUrl = 'kyc_aadhar_url';
  static const String _prefKycPanUrl = 'kyc_pan_url';
  static const String _prefVehicleName = 'vehicle_name';
  static const String _prefVehicleLicensePlate = 'vehicle_license_plate';
  static const String _prefVehicleRawJson = 'vehicle_raw_json';
  static const String _prefBankDocName = 'bank_doc_name';
  static const String _prefBankAccountName = 'bank_account_name';
  static const String _prefBankRawJson = 'bank_raw_json';
  static const String _prefIsOnline = 'is_online';
  static const String _prefPermForeground = 'perm_foreground_location';
  static const String _prefPermBackground = 'perm_background_location';
  static const String _prefPermNotification = 'perm_notification';
  static const String _prefLicenseRequiresReupload =
      'license_requires_reupload';
  static const String _prefThemeMode = 'theme_mode';
  static const String _prefBackgroundColor = 'background_color';
  static const String _prefAccentColor = 'accent_color';
  static const String _prefActiveOrderId = 'active_order_id';
  static const String _prefActiveTripId = 'active_trip_id';
  static const String _prefActiveOrderIds = 'active_order_ids';
  static const String _prefActiveTripIdsMap = 'active_trip_ids_map';
  // Per-driver keys so multiple users on the same device don't share avg data.
  static String _prefTotalTripTimeTodayMs(String driver) =>
      'total_trip_time_today_ms_$driver';
  static String _prefTripTimeSavedDate(String driver) =>
      'trip_time_saved_date_$driver';
  static const int maxConcurrentOrders = 3;
  static const int _profileImageMaxBytes = 5 * 1024 * 1024;
  static const int _profileImageMinDimension = 300;
  static const int _profileImageMaxDimension = 5000;
  static const double _profileImageMinAspectRatio = 0.75;
  static const double _profileImageMaxAspectRatio = 1.33;
  static const Set<String> _profileImageAllowedExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
  };

  final Random _random = Random();
  final Map<String, VerificationStatus> _kycStatus = {
    'idProof': VerificationStatus.notSubmitted,
    'drivingLicense': VerificationStatus.notSubmitted,
    'selfie': VerificationStatus.notSubmitted,
  };
  final Map<String, double> _kycProgress = {
    'idProof': 0,
    'drivingLicense': 0,
    'selfie': 0,
  };
  final List<AppNotice> _notices = <AppNotice>[
    AppNotice(
      title: 'Weekly incentive unlocked',
      message: 'Complete 18 deliveries today for an extra Rs.180 bonus.',
      time: DateTime.now().subtract(const Duration(minutes: 20)),
    ),
    AppNotice(
      title: 'Payout update',
      message: 'Last payout has been sent to your registered account.',
      time: DateTime.now().subtract(const Duration(hours: 3)),
    ),
  ];

  String _languageCode = '';
  bool _bootstrapped = false;
  bool _isLoggedIn = false;
  bool _rememberMe = false;
  bool _profileCompleted = false;
  bool _kycCompleted = false;
  bool _licenseRequiresReupload = false;
  String? _sessionToken;
  String _tokenType = 'Bearer';
  String? _refreshToken;
  // Cached result of buildAuthHeaders() — invalidated when token changes.
  Map<String, String>? _cachedAuthHeaders;
  String? _cachedAuthHeadersKey;
  // Cached profileCompleteness — invalidated by fingerprint of inputs.
  ProfileCompleteness? _cachedProfileCompleteness;
  String? _cachedProfileCompletenessKey;
  String? _clientId;
  String? _apiKey;
  String? _apiSecret;
  String? _configVersion;
  String? _driverName;
  String? _existingLicenseNo;
  String? _existingAadharNo;
  String? _existingPanNo;
  String? _existingLicenseUrl;
  String? _existingAadharUrl;
  String? _existingPanUrl;
  String? _existingIssuingDate;
  String? _existingExpiryDate;
  bool _isRefreshing = false;

  String? _registrationToken;
  String? _pendingRegistrationMobile;

  PartnerProfile? _profile;
  LoggedPartnerProfileDetails? _loggedProfileDetails;
  bool _profileDetailsLoading = false;
  String? _profileDetailsError;
  bool _profileImageSyncing = false;
  String? _profileImageSyncError;
  VehicleDetails? _vehicle;
  Map<String, dynamic>? _submittedVehicleRaw;
  BankDetails? _bank;
  Map<String, dynamic>? _submittedBankRaw;
  List<String> _uomOptions = <String>[];
  List<String> _vehicleFuelOptions = <String>[];
  Set<String> _vehicleRequiredFields = <String>{};
  PermissionState _permissionState = const PermissionState();

  bool _isOnline = false;
  DateTime? _onlineSince;
  Duration _completedDutyToday = Duration.zero;
  int _completedTripsToday = 0;
  Duration _totalTripTimeToday = Duration.zero;
  final Map<String, DateTime> _tripAcceptedTimes = {};
  final Set<String> _sessionTripAcceptances = {};
  bool _availabilitySyncing = false;
  bool _isTracking = false;
  int _trackingInterval = 10;
  String _liveCoordinates = '28.6139, 77.2090';
  double? _currentLatitude;
  double? _currentLongitude;
  String? _currentLocationLabel;
  String? _selectedStoreName;
  String? _profileImagePath;
  String? _serverProfileImageUrl;
  StreamSubscription<Position>? _positionStream;

  ThemeMode _themeMode = ThemeMode.system;
  int _backgroundColorValue = 0xFFF0F4FA;
  int _accentColorValue = 0xFF1C4E80;

  bool _isConnected = true;
  bool _showRetryButton = true;
  bool _isInitialized = false;
  StreamSubscription<bool>? _connectivitySubscription;

  DeliveryOrder? _incomingOrder;
  final List<DeliveryOrder> _activeOrders = <DeliveryOrder>[];
  final Map<String, String> _activeTripIds = <String, String>{};
  int _currentlyViewedOrderIndex = 0;
  final List<DeliveryOrder> _availableOrders = <DeliveryOrder>[];
  final List<DeliveryOrder> _acceptedOrders = <DeliveryOrder>[];
  final ExternalDeliveryRepository _orderRepository =
      ExternalDeliveryRepository();
  bool _isLoadingOrders = false;
  String? _orderLoadingError;
  bool _isFetchingActiveOrder = false;
  Timer? _liveLocationTimer;
  StreamSubscription<Map<String, dynamic>?>? _locationPingSubscription;
  Timer? _orderTimer;
  int _orderElapsedSeconds = 0;
  DateTime? _orderStartTime;
  GeoLocation? _partnerLiveLocation;

  EarningsSummary _earnings = const EarningsSummary(
    today: 0.0,
    week: 0.0,
    total: 0.0,
    pendingPayout: 0.0,
  );

  PerformanceMetrics _performance = const PerformanceMetrics(
    rating: 0.0,
    acceptanceRate: 0,
    completionRate: 0,
    totalDeliveries: 0,
  );

  final PartnerTimingLogDao? _timingDao;
  final Set<String> _recentEventKeys = {};

  AppController({PartnerTimingLogDao? timingDao}) : _timingDao = timingDao;

  // Public entry-point for UI-triggered events (stop_delivered, stop_failed,
  // trip_completed). The 10-second dedup window prevents double-fires from
  // rapid taps while the action is still in flight.
  void recordTimingEvent({
    required String eventType,
    String? tripRef,
    String? stopRef,
  }) {
    final key = '$tripRef:$stopRef:$eventType';
    if (_recentEventKeys.contains(key)) return;
    _recentEventKeys.add(key);
    Future.delayed(
      const Duration(seconds: 10),
      () => _recentEventKeys.remove(key),
    );
    if (eventType == TimingEventType.tripAccepted && tripRef != null) {
      if (!_sessionTripAcceptances.contains(tripRef)) {
        _sessionTripAcceptances.add(tripRef);
        _tripAcceptedTimes[tripRef] = DateTime.now();
      }
    } else if (eventType == TimingEventType.tripCompleted) {
      _completedTripsToday++;
      if (tripRef != null) {
        final start = _tripAcceptedTimes.remove(tripRef);
        if (start != null) {
          final d = DateTime.now().difference(start);
          if (!d.isNegative) _totalTripTimeToday += d;
        }
      }
      _persistTripTimeToday();
      notifyListeners();
    }
    _writeTimingEvent(eventType: eventType, tripRef: tripRef, stopRef: stopRef);
  }

  void _writeTimingEvent({
    required String eventType,
    String? tripRef,
    String? stopRef,
    String? remarks,
    String? driverOverride,
  }) {
    final dao = _timingDao;
    if (dao == null) return;
    final driver =
        driverOverride ?? _driverName ?? _profile?.mobile ?? 'unknown';
    final now = DateTime.now().toIso8601String();
    final uuid = const Uuid().v4();
    unawaited(
      dao
          .insertEvent(
            PartnerTimingLogsCompanion(
              eventUuid: Value(uuid),
              partner: Value(driver),
              eventType: Value(eventType),
              eventTime: Value(now),
              tripName: Value(tripRef),
              stopName: Value(stopRef),
              remarks: Value(remarks),
              createdAt: Value(now),
            ),
          )
          .then((_) {
            TimingSyncEngine().triggerFlush();
          })
          .catchError((Object _) {}),
    );
  }

  bool get bootstrapped => _bootstrapped;
  bool get isLoggedIn => _isLoggedIn;
  String? get sessionToken => _sessionToken;
  String? get apiKey => _apiKey;
  String? get apiSecret => _apiSecret;
  bool get rememberMe => _rememberMe;
  bool get profileCompleted => _profileCompleted;
  bool get kycCompleted => _kycCompleted;
  String get languageCode => _languageCode;
  String? get configVersion => _configVersion;
  PartnerProfile? get profile => _profile;
  LoggedPartnerProfileDetails? get loggedProfileDetails =>
      _loggedProfileDetails;
  String? get loggedUser =>
      _loggedProfileDetails?.loggedUser ?? _profile?.email;
  bool get profileDetailsLoading => _profileDetailsLoading;
  String? get profileDetailsError => _profileDetailsError;
  bool get profileImageSyncing => _profileImageSyncing;
  String? get profileImageSyncError => _profileImageSyncError;
  Map<String, VerificationStatus> get kycStatus => _kycStatus;
  Map<String, double> get kycProgress => _kycProgress;
  VehicleDetails? get vehicle => _vehicle;
  Map<String, dynamic>? get submittedVehicleRaw => _submittedVehicleRaw;
  BankDetails? get bank => _bank;
  Map<String, dynamic>? get submittedBankRaw => _submittedBankRaw;
  List<String> get uomOptions => List<String>.unmodifiable(_uomOptions);
  List<String> get vehicleFuelOptions =>
      List<String>.unmodifiable(_vehicleFuelOptions);
  Set<String> get vehicleRequiredFields =>
      Set<String>.unmodifiable(_vehicleRequiredFields);
  PermissionState get permissionState => _permissionState;
  bool get isOnline => _isOnline;
  DateTime? get onlineSince => _onlineSince;
  Duration get completedDutyToday => _completedDutyToday;
  int get completedTripsToday => _completedTripsToday;
  Duration get avgTripDurationToday => _completedTripsToday > 0
      ? Duration(milliseconds: _totalTripTimeToday.inMilliseconds ~/ _completedTripsToday)
      : Duration.zero;
  bool get availabilitySyncing => _availabilitySyncing;
  bool get isTracking => _isTracking;
  int get trackingInterval => _trackingInterval;
  String get liveCoordinates => _liveCoordinates;
  double? get currentLatitude => _currentLatitude;
  double? get currentLongitude => _currentLongitude;
  String? get currentLocationLabel => _currentLocationLabel;
  String? get selectedStoreName => _selectedStoreName;
  String? get profileImagePath => _profileImagePath;
  String? get serverProfileImageUrl => _serverProfileImageUrl;
  String? get serverProfileImageFullUrl {
    if (_serverProfileImageUrl == null) return null;
    return _serverProfileImageUrl!.startsWith('http')
        ? _serverProfileImageUrl
        : '${ApiConstants.erpBaseUrl}$_serverProfileImageUrl';
  }

  ThemeMode get themeMode => _themeMode;
  Color get backgroundColor => Color(_backgroundColorValue);
  Color get accentColor => Color(_accentColorValue);
  bool get hasSelectedLocation =>
      _currentLatitude != null && _currentLongitude != null;
  DeliveryOrder? get incomingOrder => _incomingOrder;

  // Multi-order getters
  List<DeliveryOrder> get activeOrders => List<DeliveryOrder>.unmodifiable(
    _activeOrders.length > maxConcurrentOrders
        ? _activeOrders.sublist(0, maxConcurrentOrders)
        : _activeOrders,
  );
  int get activeOrderCount => _activeOrders.length;
  bool get canAcceptMoreOrders => _activeOrders.length < maxConcurrentOrders;
  int get currentlyViewedOrderIndex => _currentlyViewedOrderIndex;

  // Backward-compatible single-order getters (returns currently viewed order)
  DeliveryOrder? get activeOrder => _activeOrders.isEmpty
      ? null
      : _activeOrders[_currentlyViewedOrderIndex.clamp(
          0,
          _activeOrders.length - 1,
        )];
  String? get activeTripId {
    final order = activeOrder;
    if (order == null) return null;
    return _activeTripIds[order.orderId];
  }

  String? tripIdForOrder(String orderId) => _activeTripIds[orderId];

  void createMockActiveOrder() {
    if (_activeOrders.isEmpty) {
      final mockOrder = DeliveryOrder(
        orderId: '#OD${3000 + _random.nextInt(999)}',
        customerName: 'Sneha Gupta',
        customerPhone: '9876512345',
        deliveryAddress: 'Saket, New Delhi - 110017',
        storeId: 'STORE200',
        storeName: 'Pizza Palace',
        storeContact: '9876598765',
        storeAddress: 'Dwarka, New Delhi - 110075',
        orderItems: <OrderItem>[
          const OrderItem(name: 'Pepperoni Pizza', quantity: 2, price: 450),
          const OrderItem(name: 'Garlic Bread', quantity: 1, price: 120),
          const OrderItem(name: 'Cola', quantity: 2, price: 60),
        ],
        orderStatus: OrderStatus.accepted,
        latitude: 28.5692,
        longitude: 77.1538,
        pickup: 'Dwarka, New Delhi',
        drop: 'Saket, New Delhi',
        deliveryInstructions: 'Ring bell twice',
        paymentMode: 'Online',
        distanceKm: 5.2,
        estimatedEarnings: 145,
        assignmentStatus: OrderAssignmentStatus.assigned,
      );
      _activeOrders.add(mockOrder);
      notifyListeners();
    }
  }


  EarningsSummary get earnings => _earnings;

  bool get isOrderTimerRunning =>
      _orderTimer != null && _orderStartTime != null;

  String get orderElapsedTime {
    final hours = _orderElapsedSeconds ~/ 3600;
    final minutes = (_orderElapsedSeconds % 3600) ~/ 60;
    final seconds = _orderElapsedSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  int get orderTotalSeconds => _orderElapsedSeconds;

  void startOrderTimer() {
    if (_orderTimer != null) return;
    _orderStartTime = DateTime.now();
    _orderElapsedSeconds = 0;
    _orderTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _orderElapsedSeconds++;
      notifyListeners();
    });
    notifyListeners();
  }

  int stopOrderTimer() {
    _orderTimer?.cancel();
    _orderTimer = null;
    final finalSeconds = _orderElapsedSeconds;
    notifyListeners();
    return finalSeconds;
  }

  void resetOrderTimer() {
    _orderTimer?.cancel();
    _orderTimer = null;
    _orderStartTime = null;
    _orderElapsedSeconds = 0;
    notifyListeners();
  }

  PerformanceMetrics get performance => _performance;
  List<AppNotice> get notices => List<AppNotice>.unmodifiable(_notices);
  bool get isConnected => _isConnected;
  // Offline mode: app works without internet. The full-screen "Oops" overlay
  // is replaced by the slim banner in AppShell (OfflineStatusIndicator).
  // Screens that genuinely require internet (e.g. OTP login) should gate
  // their actions on `isConnected` themselves rather than relying on a
  // global overlay.
  bool get showNoInternetOverlay => false;
  bool get showRetryButton => _showRetryButton;
  bool get isInitialized => _isInitialized;

  String? get driverName => _driverName;
  String? get existingLicenseNo => _existingLicenseNo;
  String? get existingAadharNo => _existingAadharNo;
  String? get existingPanNo => _existingPanNo;
  String? get existingLicenseUrl => _existingLicenseUrl;
  String? get existingAadharUrl => _existingAadharUrl;
  String? get existingPanUrl => _existingPanUrl;
  String? get existingIssuingDate => _existingIssuingDate;
  String? get existingExpiryDate => _existingExpiryDate;
  String? get registrationToken => _registrationToken;
  String? get pendingRegistrationMobile => _pendingRegistrationMobile;

  bool get allKycApproved => _kycStatus.values.every(
    (status) => status == VerificationStatus.approved,
  );

  bool get isKycComplete => _kycCompleted;
  bool get licenseRequiresReupload => _licenseRequiresReupload;

  bool get canGoOnline =>
      _kycCompleted &&
      _vehicle != null &&
      (_bank?.verified ?? false) &&
      hasSelectedLocation &&
      _permissionState.allGranted;

  ProfileCompleteness get profileCompleteness {
    final hasPhoto = _profileImagePath != null || _serverProfileImageUrl != null;
    final hasLocation = hasSelectedLocation;
    final key = '${_profile?.fullName}_${hasPhoto}_${_kycCompleted}_'
        '${_vehicle != null}_${_bank != null}_${hasLocation}_'
        '${_permissionState.allGranted}';
    if (_cachedProfileCompleteness != null && _cachedProfileCompletenessKey == key) {
      return _cachedProfileCompleteness!;
    }

    final List<ProfileCompletenessItem> items = <ProfileCompletenessItem>[
      ProfileCompletenessItem(
        name: 'profile_basic_profile',
        description: 'profile_basic_profile_desc',
        isCompleted: _profile != null && _profile!.fullName.isNotEmpty,
        route: AppRoutes.profile,
      ),
      ProfileCompletenessItem(
        name: 'profile_photo',
        description: 'profile_photo_desc',
        isCompleted: hasPhoto,
        route: AppRoutes.profile,
      ),
      ProfileCompletenessItem(
        name: 'kyc_documents',
        description: 'kyc_documents_desc',
        isCompleted: _kycCompleted,
        route: AppRoutes.kycDocuments,
      ),
      ProfileCompletenessItem(
        name: 'vehicle_details',
        description: 'vehicle_details_desc',
        isCompleted: _vehicle != null,
        route: AppRoutes.vehicleDetails,
      ),
      ProfileCompletenessItem(
        name: 'bank_account',
        description: 'bank_account_desc',
        isCompleted: _bank != null,
        route: AppRoutes.bankSetup,
      ),
      ProfileCompletenessItem(
        name: 'delivery_zone',
        description: 'delivery_zone_desc',
        isCompleted: hasLocation,
        route: AppRoutes.currentLocation,
      ),
      ProfileCompletenessItem(
        name: 'permissions',
        description: 'permissions_desc',
        isCompleted: _permissionState.allGranted,
        route: AppRoutes.permission,
      ),
    ];

    final int completedCount = items.where((item) => item.isCompleted).length;
    final int totalCount = items.length;
    final double percentage = totalCount > 0 ? completedCount / totalCount : 0;

    _cachedProfileCompleteness = ProfileCompleteness(
      percentage: percentage,
      items: items,
      completedCount: completedCount,
      totalCount: totalCount,
    );
    _cachedProfileCompletenessKey = key;
    return _cachedProfileCompleteness!;
  }

  Future<void> bootstrap() async {
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    _configVersion = 'cfg_2026_02_16';

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await SecureTokenStorage.migrateFromPreferences(prefs);
    _languageCode = prefs.getString(_prefLanguageCode) ?? '';
    _sessionToken = await SecureTokenStorage.read(
      SecureTokenStorage.accessToken,
    );
    _tokenType =
        _nullIfBlank(
          await SecureTokenStorage.read(SecureTokenStorage.tokenType),
        ) ??
        'Bearer';
    _refreshToken = _nullIfBlank(
      await SecureTokenStorage.read(SecureTokenStorage.refreshToken),
    );
    _clientId = _nullIfBlank(
      await SecureTokenStorage.read(SecureTokenStorage.clientId),
    );
    _apiKey = _nullIfBlank(
      await SecureTokenStorage.read(SecureTokenStorage.apiKey),
    );
    _apiSecret = _nullIfBlank(
      await SecureTokenStorage.read(SecureTokenStorage.apiSecret),
    );
    _rememberMe = prefs.getBool(_prefRememberMe) ?? false;
    _profileCompleted = prefs.getBool(_prefProfileCompleted) ?? false;
    _kycCompleted = prefs.getBool(_prefKycCompleted) ?? false;
    _existingLicenseNo = _nullIfBlank(prefs.getString(_prefKycLicenseNo));
    _existingAadharNo = _nullIfBlank(prefs.getString(_prefKycAadharNo));
    _existingPanNo = _nullIfBlank(prefs.getString(_prefKycPanNo));
    _existingLicenseUrl = _nullIfBlank(prefs.getString(_prefKycLicenseUrl));
    _existingAadharUrl = _nullIfBlank(prefs.getString(_prefKycAadharUrl));
    _existingPanUrl = _nullIfBlank(prefs.getString(_prefKycPanUrl));
    final String? bankRawJson = _nullIfBlank(prefs.getString(_prefBankRawJson));
    if (bankRawJson != null) {
      final Map<String, dynamic> decoded = _decodeJsonMap(bankRawJson);
      if (decoded.isNotEmpty) {
        _submittedBankRaw = decoded;
        _bank = _bankFromApiData(decoded);
      }
    }
    final String? vehicleRawJson = _nullIfBlank(
      prefs.getString(_prefVehicleRawJson),
    );
    if (vehicleRawJson != null) {
      final Map<String, dynamic> decoded = _decodeJsonMap(vehicleRawJson);
      if (decoded.isNotEmpty) {
        _submittedVehicleRaw = decoded;
        _vehicle = _vehicleFromApiData(decoded);
      }
    }
    _isOnline = prefs.getBool(_prefIsOnline) ?? false;
    // Read driver name early so the DB query below filters by the correct partner.
    final String? earlyDriverName = _nullIfBlank(prefs.getString(_prefDriverName));
    if (_timingDao != null) {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final rows = await _timingDao.getEventsInRange(
        startOfDay,
        endOfDay,
        partner: earlyDriverName,
      );
      final logins = rows.where((r) => r.eventType == TimingEventType.login).toList();
      final logouts = rows.where((r) => r.eventType == TimingEventType.logout).toList();
      if (logins.isNotEmpty && logouts.isNotEmpty) {
        final diff = DateTime.parse(logouts.last.eventTime)
            .difference(DateTime.parse(logins.first.eventTime));
        if (!diff.isNegative) _completedDutyToday = diff;
      }
      if (_isOnline && logins.isNotEmpty) {
        _onlineSince = DateTime.tryParse(logins.last.eventTime);
      }
      _completedTripsToday = rows
          .where((r) => r.eventType == TimingEventType.tripCompleted)
          .length;

      // Restore avg trip duration: prefs is the source of truth (saved after
      // every trip_completed). Fall back to DB pairing if prefs has no entry
      // for today (first run after an app update, etc.).
      final now2 = DateTime.now();
      final todayStr = '${now2.year}-${now2.month.toString().padLeft(2, '0')}-${now2.day.toString().padLeft(2, '0')}';
      final driverKey = earlyDriverName ?? '';
      final savedDate = driverKey.isNotEmpty ? prefs.getString(_prefTripTimeSavedDate(driverKey)) : null;
      if (savedDate == todayStr) {
        final savedMs = prefs.getInt(_prefTotalTripTimeTodayMs(driverKey)) ?? 0;
        _totalTripTimeToday = Duration(milliseconds: savedMs);
      } else {
        // Prefs is from a previous day — compute from DB event pairs instead.
        final acceptedTimes = <String, DateTime>{};
        for (final r in rows) {
          if (r.eventType == TimingEventType.tripAccepted && r.tripName != null) {
            acceptedTimes[r.tripName!] = DateTime.parse(r.eventTime);
          }
        }
        var restoredTripTime = Duration.zero;
        for (final r in rows.where((r) => r.eventType == TimingEventType.tripCompleted && r.tripName != null)) {
          final start = acceptedTimes[r.tripName!];
          if (start != null) {
            final d = DateTime.parse(r.eventTime).difference(start);
            if (!d.isNegative) restoredTripTime += d;
          }
        }
        _totalTripTimeToday = restoredTripTime;
      }
      // Mark already-recorded trip acceptances so the screen doesn't re-fire them.
      // For trips still in progress (accepted today but NOT yet completed today),
      // also restore _tripAcceptedTimes so the duration is captured when they finish.
      final completedTodayRefs = rows
          .where((r) => r.eventType == TimingEventType.tripCompleted && r.tripName != null)
          .map((r) => r.tripName!)
          .toSet();
      for (final r in rows) {
        if (r.eventType == TimingEventType.tripAccepted && r.tripName != null) {
          _sessionTripAcceptances.add(r.tripName!);
          if (!completedTodayRefs.contains(r.tripName!)) {
            // Trip still in progress — restore start time from DB.
            _tripAcceptedTimes[r.tripName!] = DateTime.parse(r.eventTime);
          }
        }
      }
    }
    final String? persistedActiveOrderId = _nullIfBlank(
      prefs.getString(_prefActiveOrderId),
    );
    final String? persistedActiveOrderIds = _nullIfBlank(
      prefs.getString(_prefActiveOrderIds),
    );

    await PartnerWidgetManager.initialize();
    _currentLatitude = prefs.getDouble(_prefCurrentLat);
    _currentLongitude = prefs.getDouble(_prefCurrentLng);
    _currentLocationLabel = _nullIfBlank(
      prefs.getString(_prefCurrentLocationLabel),
    );
    _selectedStoreName = _nullIfBlank(prefs.getString(_prefSelectedStore));
    _driverName = _nullIfBlank(prefs.getString(_prefDriverName));
    _profileImagePath = _nullIfBlank(prefs.getString(_prefProfileImagePath));
    _serverProfileImageUrl = _nullIfBlank(
      prefs.getString(_prefServerProfileImageUrl),
    );
    final int themeModeIndex =
        prefs.getInt(_prefThemeMode) ?? ThemeMode.system.index;
    _themeMode =
        ThemeMode.values[themeModeIndex.clamp(0, ThemeMode.values.length - 1)];
    _backgroundColorValue = prefs.getInt(_prefBackgroundColor) ?? 0xFFF0F4FA;
    _accentColorValue = prefs.getInt(_prefAccentColor) ?? 0xFF1C4E80;
    _permissionState = PermissionState(
      foregroundLocation: prefs.getBool(_prefPermForeground) ?? false,
      backgroundLocation: prefs.getBool(_prefPermBackground) ?? false,
      notification: prefs.getBool(_prefPermNotification) ?? false,
    );
    _licenseRequiresReupload =
        prefs.getBool(_prefLicenseRequiresReupload) ?? false;
    _isLoggedIn = _sessionToken != null;
    if (_isLoggedIn) {
      final String fullName =
          prefs.getString(_prefFullName) ?? 'Delivery Partner';
      final String mobile = prefs.getString(_prefMobile) ?? '';
      final String? email = _nullIfBlank(prefs.getString(_prefEmail));
      _profile = PartnerProfile(
        fullName: fullName,
        mobile: mobile,
        email: email,
      );
    }

    // Refresh the access token only if it's actually expired (or
    // about to be — 30s skew buffer). Otherwise keep the existing
    // bearer token and let the reactive 401 path inside
    // _authorizedGet handle anything that surprises us. Without this
    // gate every cold start would hit /get_token and create a new
    // OAuth Bearer Token row server-side.
    if (_isLoggedIn &&
        _refreshToken != null &&
        _refreshToken!.trim().isNotEmpty &&
        _clientId != null &&
        _clientId!.trim().isNotEmpty) {
      final DateTime? expiresAt = await _readAccessTokenExpiry();
      final DateTime now = DateTime.now().toUtc();
      final bool needsRefresh =
          expiresAt == null ||
          now.isAfter(expiresAt.subtract(const Duration(seconds: 30)));
      if (needsRefresh) {
        final bool refreshed = await refreshSession();
        if (!refreshed) {
          _isLoggedIn = false;
          _sessionToken = null;
          _refreshToken = null;
          _tokenType = 'Bearer';
          _clientId = null;
          _apiKey = null;
          _apiSecret = null;
          _profile = null;
          _profileCompleted = false;
          _kycCompleted = false;
          await SecureTokenStorage.deleteAll();
        }
      } else {
      }
    }

    if (persistedActiveOrderId != null || persistedActiveOrderIds != null) {
      unawaited(_restoreActiveOrder(persistedActiveOrderId ?? ''));
    } else {
      _activeOrders.clear();
      _activeTripIds.clear();
      _acceptedOrders.clear();
    }

    await PartnerWidgetManager.updateWidget(
      isOnline: _isOnline,
      todayEarnings: _earnings.today,
      activeOrder: activeOrder,
    );

    await syncPermissionsFromOS();

    _bootstrapped = true;

    // Subscribe to FCM only when driver is online so offline drivers
    // don't receive order notifications.
    if (_isOnline) unawaited(FCMService().subscribe(this));

    notifyListeners();

    // Background-fetch backend data so profile completeness is correct on open
    if (_isLoggedIn) {
      unawaited(_backgroundSync());
    }
  }

  /// Fetches profile first (so _driverName is set), then hydrates vehicle
  /// and bank in parallel. Used on bootstrap, login, and registration so the
  /// profile completeness section is correct without a manual refresh.
  Future<void> _backgroundSync() async {
    await fetchLoggedInEmployeeDriverProfile();
    await Future.wait(<Future<void>>[
      hydrateVehicleFromBackend(),
      hydrateBankFromBackend(),
    ]);
    // Restore an in-progress order that was lost when SharedPreferences were
    // cleared (e.g. after logout/login). Only runs when there's no order in
    // local state — normal boot restores via _restoreActiveOrder instead.
    if (_activeOrders.isEmpty &&
        _driverName != null &&
        _driverName!.isNotEmpty) {
      await _tryRestoreActiveOrderByDriver();
    }
  }

  Future<void> initializeConnectivity() async {
    final ConnectivityService connectivityService = ConnectivityService();
    await connectivityService.initialize();
    _isConnected = connectivityService.isConnected;
    _showRetryButton = true;
    notifyListeners();

    _connectivitySubscription?.cancel();
    _connectivitySubscription = connectivityService.connectivityStream.listen((
      bool isConnected,
    ) {
      _onConnectivityChanged(isConnected);
    });
    connectivityService.startMonitoring();
    _isInitialized = true;
    notifyListeners();
  }

  void _onConnectivityChanged(bool isConnected) {
    _isConnected = isConnected;
    _showRetryButton = true;
    notifyListeners();
  }

  Future<bool> checkConnectivity() async {
    final ConnectivityService connectivityService = ConnectivityService();
    final bool hasConnection = await connectivityService.checkConnectivity();
    _isConnected = hasConnection;
    _showRetryButton = true;
    notifyListeners();
    return hasConnection;
  }

  Future<bool> retryConnection() async {
    _showRetryButton = false;
    notifyListeners();

    final bool hasConnection = await checkConnectivity();
    return hasConnection;
  }

  void setAppResumed(bool isResumed) {
    notifyListeners();
  }

  void setFirstFrameBuilt(bool built) {
    notifyListeners();
  }

  void setLanguage(String code) {
    final String normalized = AppStrings.isSupportedLanguageCode(code)
        ? code
        : 'en';
    _languageCode = normalized;
    _writePref((SharedPreferences prefs) {
      return prefs.setString(_prefLanguageCode, normalized);
    });
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _writePref((SharedPreferences prefs) {
      return prefs.setInt(_prefThemeMode, mode.index);
    });
    notifyListeners();
  }

  void setBackgroundColor(Color color) {
    _backgroundColorValue = color.toARGB32();
    _writePref((SharedPreferences prefs) {
      return prefs.setInt(_prefBackgroundColor, _backgroundColorValue);
    });
    notifyListeners();
  }

  void setAccentColor(Color color) {
    _accentColorValue = color.toARGB32();
    _writePref((SharedPreferences prefs) {
      return prefs.setInt(_prefAccentColor, _accentColorValue);
    });
    notifyListeners();
  }

  void resetThemeToDefaults() {
    _themeMode = ThemeMode.system;
    _backgroundColorValue = 0xFFF0F4FA;
    _accentColorValue = 0xFF1C4E80;
    _writePref((SharedPreferences prefs) async {
      await prefs.setInt(_prefThemeMode, ThemeMode.system.index);
      await prefs.setInt(_prefBackgroundColor, _backgroundColorValue);
      await prefs.setInt(_prefAccentColor, _accentColorValue);
      return true;
    });
    notifyListeners();
  }

  void setRememberMe(bool value) {
    _rememberMe = value;
    _writePref((SharedPreferences prefs) {
      return prefs.setBool(_prefRememberMe, value);
    });
    notifyListeners();
  }

  Future<void> completeProfile() async {
    _profileCompleted = true;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefProfileCompleted, true);
    notifyListeners();
  }

  Future<void> updateProfile({
    String? fullName,
    String? email,
    String? mobile,
  }) async {
    if (_profile != null) {
      _profile = _profile!.copyWith(
        fullName: fullName,
        email: email,
        mobile: mobile,
      );
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await Future.wait(<Future<bool>>[
        prefs.setString(_prefFullName, _profile!.fullName),
        if (_profile!.email != null)
          prefs.setString(_prefEmail, _profile!.email!),
        prefs.setString(_prefMobile, _profile!.mobile),
      ]);
      notifyListeners();
    }
  }

  Future<String?> updateProfileAndSync({
    String? fullName,
    String? email,
    String? mobile,
  }) async {
    await updateProfile(fullName: fullName, email: email, mobile: mobile);

    final String? normalizedName = _nullIfBlank(fullName);
    final String? normalizedEmail = _nullIfBlank(email);
    final String? normalizedMobile = _nullIfBlank(mobile);

    try {
      if (_loggedProfileDetails?.driver == null) {
        await fetchLoggedInEmployeeDriverProfile(forceRefresh: true);
      }

      final String? driverName = _nullIfBlank(
        _loggedProfileDetails?.driver?['name']?.toString(),
      );
      if (driverName == null) {
        return 'Basic information saved on this device. Driver link missing for backend sync.';
      }

      final Map<String, dynamic> driverPayload = <String, dynamic>{};
      if (normalizedName != null) {
        driverPayload['full_name'] = normalizedName;
      }
      if (normalizedMobile != null) {
        driverPayload['cell_number'] = normalizedMobile;
      }
      if (email != null) {
        driverPayload['email'] = normalizedEmail ?? '';
      }

      if (driverPayload.isNotEmpty) {
        final Uri driverUri = Uri.parse(
          '${ApiConstants.erpBaseUrl}/api/resource/Driver/${Uri.encodeComponent(driverName)}',
        );
        final Map<String, dynamic> updatedDriver = await authorizedPutJson(
          driverUri,
          driverPayload,
        );
        final Map<String, dynamic>? refreshedDriver = _extractResourceData(
          updatedDriver,
        );
        if (refreshedDriver != null) {
          _loggedProfileDetails = LoggedPartnerProfileDetails(
            loggedUser: _loggedProfileDetails?.loggedUser,
            employee: _loggedProfileDetails?.employee,
            driver: refreshedDriver,
          );
          notifyListeners();
        }
      }

      final String? employeeName = await _resolveEmployeeNameForProfileSync();
      if (employeeName != null) {
        final Map<String, dynamic> employeePayload =
            await _buildEmployeeProfileUpdatePayload(
              fullName: normalizedName,
              email: email != null ? normalizedEmail : '',
              mobile: normalizedMobile,
            );
        if (employeePayload.isNotEmpty) {
          final Uri employeeUri = Uri.parse(
            '${ApiConstants.erpBaseUrl}/api/resource/Employee/${Uri.encodeComponent(employeeName)}',
          );
          final Map<String, dynamic> updatedEmployee = await authorizedPutJson(
            employeeUri,
            employeePayload,
          );
          final Map<String, dynamic>? refreshedEmployee = _extractResourceData(
            updatedEmployee,
          );
          if (refreshedEmployee != null) {
            _loggedProfileDetails = LoggedPartnerProfileDetails(
              loggedUser: _loggedProfileDetails?.loggedUser,
              employee: refreshedEmployee,
              driver: _loggedProfileDetails?.driver,
            );
            notifyListeners();
          }
        }
      }

      final String? userName = _resolveUserNameForProfileSync();
      if (userName != null) {
        await _updateUserProfileAndMaybeRename(
          currentUserName: userName,
          fullName: normalizedName,
          email: email != null ? normalizedEmail : null,
          mobile: normalizedMobile,
        );
      }

      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  Future<void> setProfileImagePath(String? path) async {
    _profileImagePath = _nullIfBlank(path);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (_profileImagePath != null) {
      await prefs.setString(_prefProfileImagePath, _profileImagePath!);
    } else {
      await prefs.remove(_prefProfileImagePath);
    }
    notifyListeners();
  }

  Future<String?> removeProfileImageAndSync() async {
    if (_profileImageSyncing) {
      return 'Profile image update is already in progress';
    }

    _profileImageSyncing = true;
    _profileImageSyncError = null;
    notifyListeners();

    try {
      await setProfileImagePath(null);

      final String? employeeName = await _resolveEmployeeNameForProfileSync();
      if (employeeName != null) {
        final Uri employeeUri = Uri.parse(
          '${ApiConstants.erpBaseUrl}/api/resource/Employee/${Uri.encodeComponent(employeeName)}',
        );
        final Map<String, dynamic> payload = await authorizedPutJson(
          employeeUri,
          <String, dynamic>{'image': ''},
        );
        final Map<String, dynamic>? refreshedEmployee = _extractResourceData(
          payload,
        );
        _loggedProfileDetails = LoggedPartnerProfileDetails(
          loggedUser: _loggedProfileDetails?.loggedUser,
          employee: refreshedEmployee ?? _loggedProfileDetails?.employee,
          driver: _loggedProfileDetails?.driver,
        );
      }

      await _persistServerProfileImageUrl(null);

      String? userName = _resolveUserNameForProfileSync();
      if (userName == null) {
        try {
          userName = await _fetchLoggedUser();
        } catch (_) {}
      }
      await _syncUserImageField(userName: userName, imageUrl: null);
      _profileImageSyncError = null;
      return null;
    } catch (e) {
      _profileImageSyncError = e.toString().replaceFirst('Exception: ', '');
      return _profileImageSyncError;
    } finally {
      _profileImageSyncing = false;
      notifyListeners();
    }
  }

  Future<String?> updateProfileImageAndSync({
    required String pickedPath,
  }) async {
    if (_profileImageSyncing) {
      return 'Profile image update is already in progress';
    }

    final String sourcePath = pickedPath.trim();
    if (sourcePath.isEmpty || !File(sourcePath).existsSync()) {
      return 'Selected image is unavailable. Pick another image.';
    }
    // final String? imageValidationError = await _validateProfileImage(
    //   sourcePath,
    // );
    // if (imageValidationError != null) {
    //   return imageValidationError;
    // }

    _profileImageSyncing = true;
    _profileImageSyncError = null;
    notifyListeners();

    try {
      final String localPath = await _copyProfileImageToAppStorage(sourcePath);
      await setProfileImagePath(localPath);

      // Resolve identifiers (force-fetches profile if not yet loaded).
      final String? employeeName = await _resolveEmployeeNameForProfileSync();
      String? userName = _resolveUserNameForProfileSync();
      if (userName == null) {
        try {
          userName = await _fetchLoggedUser();
        } catch (_) {}
      }

      final Uri uploadUri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/method/upload_file',
      );

      String? fileUrl;

      if (employeeName != null) {
        final Map<String, dynamic> uploadPayload = await _authorizedUploadFile(
          uri: uploadUri,
          filePath: localPath,
          fields: <String, String>{
            'is_private': '0',
            'doctype': 'Employee',
            'docname': employeeName,
            'fieldname': 'image',
            'attached_to_doctype': 'Employee',
            'attached_to_name': employeeName,
            'attached_to_field': 'image',
          },
        );
        fileUrl = _extractUploadedFileUrl(uploadPayload);
        if (fileUrl == null) {
          throw Exception(
            'Image uploaded but file URL missing in server response',
          );
        }
        await _updateEmployeeImage(
          employeeName: employeeName,
          imageUrl: fileUrl,
        );
      } else if (userName != null) {
        final Map<String, dynamic> uploadPayload = await _authorizedUploadFile(
          uri: uploadUri,
          filePath: localPath,
          fields: <String, String>{
            'is_private': '0',
            'doctype': 'User',
            'docname': userName,
            'fieldname': 'user_image',
            'attached_to_doctype': 'User',
            'attached_to_name': userName,
            'attached_to_field': 'user_image',
          },
        );
        fileUrl = _extractUploadedFileUrl(uploadPayload);
        if (fileUrl == null) {
          throw Exception(
            'Image uploaded but file URL missing in server response',
          );
        }
      } else {
        throw Exception(
          'No employee or user account linked — cannot sync image to web',
        );
      }

      // Always cache the server URL locally so the avatar can fall back to it
      // even if the web-sync call below fails.
      await _persistServerProfileImageUrl(fileUrl);

      // Sync to User.user_image — errors here are non-fatal (local image works).
      final String? syncError = await _syncUserImageField(
        userName: userName,
        imageUrl: fileUrl,
      );
      _profileImageSyncError = syncError;
      // Return the sync error so the UI snack bar shows it.
      // The local image is already saved — only web sync may have failed.
      return syncError;
    } catch (e) {
      _profileImageSyncError = e.toString().replaceFirst('Exception: ', '');
      return _profileImageSyncError;
    } finally {
      _profileImageSyncing = false;
      notifyListeners();
    }
  }

  Future<String> _copyProfileImageToAppStorage(String sourcePath) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory profileDir = Directory('${docs.path}/profile_images');
    if (!profileDir.existsSync()) {
      profileDir.createSync(recursive: true);
    }

    final String ext = _fileExtension(sourcePath);
    final String targetPath =
        '${profileDir.path}/profile_${DateTime.now().millisecondsSinceEpoch}$ext';
    final File copied = await File(sourcePath).copy(targetPath);

    final String? previous = _profileImagePath;
    if (previous != null &&
        previous != copied.path &&
        previous.startsWith(profileDir.path)) {
      final oldFile = File(previous);
      if (oldFile.existsSync()) {
        oldFile.deleteSync();
      }
    }

    return copied.path;
  }

  String _fileExtension(String path) {
    final int lastSlash = path.lastIndexOf('/');
    final int lastDot = path.lastIndexOf('.');
    if (lastDot <= lastSlash) {
      return '';
    }
    return path.substring(lastDot);
  }

  Future<void> setSelectedLocation({
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    _currentLatitude = latitude;
    _currentLongitude = longitude;
    _currentLocationLabel = label?.trim().isEmpty == true
        ? null
        : label?.trim();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      prefs.setDouble(_prefCurrentLat, latitude),
      prefs.setDouble(_prefCurrentLng, longitude),
      prefs.setString(
        _prefCurrentLocationLabel,
        _currentLocationLabel ??
            '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
      ),
    ]);
    notifyListeners();
  }

  Future<void> clearSelectedLocation() async {
    _currentLatitude = null;
    _currentLongitude = null;
    _currentLocationLabel = null;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      prefs.remove(_prefCurrentLat),
      prefs.remove(_prefCurrentLng),
      prefs.remove(_prefCurrentLocationLabel),
    ]);
    notifyListeners();
  }

  Future<void> setSelectedStore(String? storeName) async {
    _selectedStoreName = storeName?.trim().isEmpty == true
        ? null
        : storeName?.trim();
    final prefs = await SharedPreferences.getInstance();
    if (_selectedStoreName != null) {
      await prefs.setString(_prefSelectedStore, _selectedStoreName!);
    } else {
      await prefs.remove(_prefSelectedStore);
    }
    notifyListeners();
  }

  String? validateMobile(String mobile) {
    return app_validators.validateMobile(mobile);
  }

  Future<String> sendOtp(String mobile) async {
    final String? mobileValidation = validateMobile(mobile);
    if (mobileValidation != null) {
      return mobileValidation;
    }

    try {
      final http.Response response = await http
          .post(
            _sendOtpUri,
            headers: _requestHeaders(),
            body: <String, String>{
              'mobile_no': mobile.trim(),
              'store_id': _storeId,
            },
          )
          .timeout(_networkTimeout);

      final Map<String, dynamic> payload = _decodeJsonMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _extractServerError(payload) ??
            'OTP request failed (${response.statusCode})';
      }

      final String? possibleError = _extractServerError(payload);
      if (possibleError != null) {
        return possibleError;
      }

      final Map<String, dynamic> responseData = _extractMethodData(payload);
      final String? responseMobile = _nullIfBlank(
        responseData['mobile_no']?.toString(),
      );
      if (responseMobile == null && payload['mobile_no'] == null) {
        return 'OTP request failed';
      }

      return 'OTP sent successfully to $mobile';
    } catch (e) {
      if (e is TimeoutException) {
        return 'Request timed out. Please try again.';
      }
      return 'Unable to connect. Check internet and try again.';
    }
  }

  bool verifyOtp(String mobile, String otp) =>
      otp.isNotEmpty && mobile.isNotEmpty;

  Future<String?> loginWithOtp({
    required String mobile,
    required String otp,
  }) async {
    final String? mobileValidation = validateMobile(mobile);
    if (mobileValidation != null) {
      return mobileValidation;
    }
    if (otp.trim().isEmpty) {
      return 'Enter OTP';
    }

    try {
      final http.Response response = await http
          .post(
            _verifyOtpUri,
            headers: _requestHeaders(),
            body: <String, String>{
              'mobile_no': mobile.trim(),
              'otp': otp.trim(),
              'store_id': _storeId,
            },
          )
          .timeout(_networkTimeout);

      final Map<String, dynamic> payload = _decodeJsonMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _extractServerError(payload) ??
            'OTP verification failed (${response.statusCode})';
      }

      final Map<String, dynamic> responseData = _extractMethodData(payload);
      final String status = (responseData['status']?.toString() ?? '')
          .toLowerCase();

      // Account not found — store registration token and signal the UI
      if (status == 'not_found') {
        _registrationToken = responseData['registration_token']?.toString();
        _pendingRegistrationMobile = mobile.trim();
        // This path returns before _persistSession, so nothing else resets the
        // previous session's KYC identity. Without this, a new user registering
        // on a reused device sees the prior driver's details on the KYC form.
        _clearKycIdentity();
        notifyListeners();
        return 'ACCOUNT_NOT_FOUND';
      }

      final String token = responseData['access_token']?.toString() ?? '';

      // If status is success and we have a token, skip _extractServerError
      // which may pick up harmless _server_messages from Frappe.
      if (status != 'success' || token.isEmpty) {
        final String? possibleError = _extractServerError(payload);
        if (possibleError != null) {
          return possibleError;
        }
        if (status.isNotEmpty && status != 'success') {
          return _nullIfBlank(responseData['message']?.toString()) ??
              'OTP verification failed';
        }
        if (token.isEmpty) {
          return 'Access token missing in verify response';
        }
      }

      final String responseMobile =
          _normalizeMobileForDisplay(responseData['mobile_no']?.toString()) ??
          mobile.trim();
      final String fullName =
          _nullIfBlank(responseData['full_name']?.toString()) ??
          'Delivery Partner';
      final String? email = _nullIfBlank(responseData['email']?.toString());

      _sessionToken = token;
      _isLoggedIn = true;
      // Successful OTP login means user exists — profile is always completed.
      _profileCompleted = true;
      _currentLatitude = null;
      _currentLongitude = null;
      _currentLocationLabel = null;
      _profile = PartnerProfile(
        fullName: fullName,
        mobile: responseMobile,
        email: email,
      );
      await _persistSession(responseData);

      // Update FCM token on login
      unawaited(FCMService().subscribe(this));

      // profileCompleted/isKycComplete/hasSelectedLocation are already final
      // at this point (set above from the verify-OTP response), so the login
      // screen can navigate immediately. Profile/vehicle/bank/order hydration
      // and duty-timing restore continue in the background and notify
      // listeners as they complete, same as the bootstrap() cold-start path.
      unawaited(() async {
        await _backgroundSync();
        await _restoreSessionFromDb();
        notifyListeners();
        _writeTimingEvent(eventType: TimingEventType.login);
      }());

      return null;
    } catch (e) {
      if (e is TimeoutException) {
        return 'Request timed out. Please try again.';
      }
      return 'Unable to connect. Check internet and try again.';
    }
  }

  /// Attempts to refresh the session using the stored refresh token
  /// via Frappe's standard OAuth2 `get_token` endpoint.
  /// Returns `true` if the token was refreshed successfully.
  Future<bool> refreshSession() async {
    if (_isRefreshing) {
      return false;
    }
    if (_refreshToken == null || _refreshToken!.trim().isEmpty) {
      return false;
    }
    if (_clientId == null || _clientId!.trim().isEmpty) {
      return false;
    }

    _isRefreshing = true;
    try {
      final http.Response response = await http
          .post(
            _refreshTokenUri,
            headers: _requestHeaders(
              contentType: 'application/x-www-form-urlencoded',
            ),
            body: <String, String>{
              'grant_type': 'refresh_token',
              'refresh_token': _refreshToken!,
              'client_id': _clientId!,
            },
          )
          .timeout(_networkTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }

      final Map<String, dynamic> data = _decodeJsonMap(response.body);

      final String? newToken = _nullIfBlank(data['access_token']?.toString());
      if (newToken == null) return false;

      _sessionToken = newToken;
      _tokenType = _nullIfBlank(data['token_type']?.toString()) ?? _tokenType;
      final String? newRefresh = _nullIfBlank(
        data['refresh_token']?.toString(),
      );
      if (newRefresh != null) {
        _refreshToken = newRefresh;
      }

      // Persist new tokens to secure storage
      await SecureTokenStorage.write(
        SecureTokenStorage.accessToken,
        _sessionToken!,
      );
      if (_tokenType.isNotEmpty) {
        await SecureTokenStorage.write(
          SecureTokenStorage.tokenType,
          _tokenType,
        );
      }
      if (newRefresh != null) {
        await SecureTokenStorage.write(
          SecureTokenStorage.refreshToken,
          newRefresh,
        );
      }

      final int? newExpiresIn = int.tryParse(
        data['expires_in']?.toString() ?? '',
      );
      await _persistAccessTokenExpiry(newExpiresIn);

      return true;
    } catch (_) {
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  /// Persist the absolute moment when the current access token will
  /// stop being valid. Used by bootstrap to decide whether the
  /// proactive refresh actually needs to fire — without this we hit
  /// /get_token on every cold start and litter the OAuth Bearer
  /// Token table with new rows.
  Future<void> _persistAccessTokenExpiry(int? expiresInSeconds) async {
    final int seconds = (expiresInSeconds == null || expiresInSeconds <= 0)
        ? 3600
        : expiresInSeconds;
    final DateTime expiresAt = DateTime.now().toUtc().add(
      Duration(seconds: seconds),
    );
    await SecureTokenStorage.write(
      SecureTokenStorage.accessTokenExpiresAt,
      expiresAt.toIso8601String(),
    );
  }

  /// Reads the persisted access-token expiry. Returns null if it has
  /// never been written, can't be parsed, or has already passed.
  Future<DateTime?> _readAccessTokenExpiry() async {
    final String? raw = await SecureTokenStorage.read(
      SecureTokenStorage.accessTokenExpiresAt,
    );
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  Future<String?> registerNewPartner({
    required String fullName,
    String? email,
  }) async {
    if (fullName.trim().isEmpty) {
      return 'Full name is required';
    }
    if (_pendingRegistrationMobile == null || _registrationToken == null) {
      return 'Registration session expired. Please verify OTP again.';
    }

    try {
      final Map<String, String> body = <String, String>{
        'mobile_no': _pendingRegistrationMobile!,
        'registration_token': _registrationToken!,
        'full_name': fullName.trim(),
        'store_id': _storeId,
      };
      if (email != null && email.trim().isNotEmpty) {
        body['email'] = email.trim();
      }

      final http.Response response = await http.post(
        _registerPartnerUri,
        headers: _requestHeaders(),
        body: body,
      );

      final Map<String, dynamic> payload = _decodeJsonMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _extractServerError(payload) ??
            'Registration failed (${response.statusCode})';
      }

      // Check response data status FIRST — _server_messages may contain
      // harmless informational messages (e.g. "Username already exists")
      // that _extractServerError would incorrectly treat as errors.
      final Map<String, dynamic> responseData = _extractMethodData(payload);
      final String status = (responseData['status']?.toString() ?? '')
          .toLowerCase();

      final String token = responseData['access_token']?.toString() ?? '';

      // If status is success and we have a token, proceed regardless of
      // any _server_messages noise from Frappe.
      if (status != 'success' || token.isEmpty) {
        final String? possibleError = _extractServerError(payload);
        if (possibleError != null) {
          return possibleError;
        }
        if (status.isNotEmpty && status != 'success') {
          return _nullIfBlank(responseData['message']?.toString()) ??
              'Registration failed';
        }
        if (token.isEmpty) {
          return 'Access token missing in registration response';
        }
      }
      if (token.isEmpty) {
        return 'Access token missing in registration response';
      }

      final String responseMobile =
          _normalizeMobileForDisplay(responseData['mobile_no']?.toString()) ??
          _pendingRegistrationMobile!;
      final String respFullName =
          _nullIfBlank(responseData['full_name']?.toString()) ??
          fullName.trim();
      final String? respEmail = _nullIfBlank(responseData['email']?.toString());

      _sessionToken = token;
      _isLoggedIn = true;
      _currentLatitude = null;
      _currentLongitude = null;
      _currentLocationLabel = null;
      _profile = PartnerProfile(
        fullName: respFullName,
        mobile: responseMobile,
        email: respEmail,
      );

      // Clear registration state
      _registrationToken = null;
      _pendingRegistrationMobile = null;

      await _persistSession(responseData);

      await _backgroundSync();
      await _restoreSessionFromDb();
      notifyListeners();

      return null;
    } catch (_) {
      return 'Unable to connect. Check internet and try again.';
    }
  }

  Future<void> _revokeTokenOnServer(String token) async {
    try {
      final http.Response response = await http
          .post(
            _revokeTokenUri,
            headers: const <String, String>{
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: <String, String>{
              'token': token,
              if (_clientId != null && _clientId!.isNotEmpty)
                'client_id': _clientId!,
            },
          )
          .timeout(_networkTimeout);
    } catch (_) {
    }
  }

  /// Calls Frappe's /api/method/logout so LoginManager.logout_log() writes an
  /// Activity Log entry for the session. `revoke_token` alone only kills the
  /// OAuth bearer token; it does not create the audit row.
  Future<void> _serverSideLogout(String bearerToken, String tokenType) async {
    try {
      final http.Response response = await http
          .post(
            _serverLogoutUri,
            headers: <String, String>{
              'Authorization':
                  '${tokenType.isEmpty ? 'Bearer' : tokenType} $bearerToken',
            },
          )
          .timeout(_networkTimeout);
    } catch (_) {
    }
  }

  Future<void> logout() async {
    // Snapshot credentials before we clear them — needed by the background
    // server-side cleanup below.
    final String? accessToRevoke = _sessionToken;
    final String? refreshToRevoke = _refreshToken;
    final String tokenTypeSnapshot = _tokenType;
    final String? driverAtLogout = _driverName ?? _profile?.mobile;
    final bool wasOnline = _isOnline;

    // Clear in-memory state first. notifyListeners() runs synchronously so
    // any listener that routes on auth state (or the login route below)
    // sees the logged-out state immediately.
    _writeTimingEvent(
      eventType: TimingEventType.logout,
      driverOverride: driverAtLogout,
    );
    _isLoggedIn = false;
    _sessionToken = null;
    _tokenType = 'Bearer';
    _refreshToken = null;
    _clientId = null;
    _apiKey = null;
    _apiSecret = null;
    _isRefreshing = false;
    _isOnline = false;
    _onlineSince = null;
    _completedDutyToday = Duration.zero;
    _completedTripsToday = 0;
    _totalTripTimeToday = Duration.zero;
    _tripAcceptedTimes.clear();
    _sessionTripAcceptances.clear();
    _isTracking = false;
    _incomingOrder = null;
    _activeOrders.clear();
    _activeTripIds.clear();
    _profile = null;
    _profileImagePath = null;
    _serverProfileImageUrl = null;
    _loggedProfileDetails = null;
    _profileDetailsError = null;
    _profileDetailsLoading = false;
    _profileCompleted = false;
    _kycCompleted = false;
    _clearKycIdentity();
    _currentLatitude = null;
    _currentLongitude = null;
    _currentLocationLabel = null;
    _driverName = null;
    _vehicle = null;
    _submittedVehicleRaw = null;
    _bank = null;
    _submittedBankRaw = null;
    _uomOptions = <String>[];
    _vehicleFuelOptions = <String>[];
    _vehicleRequiredFields = <String>{};
    _rememberMe = false;
    _earnings = const EarningsSummary(
      today: 0,
      week: 0,
      total: 0,
      pendingPayout: 0,
    );
    _performance = const PerformanceMetrics(
      rating: 0.0,
      acceptanceRate: 0,
      completionRate: 0,
      totalDeliveries: 0,
    );
    notifyListeners();

    // Local persistence — Keystore and SharedPreferences writes are fast
    // (<100ms), keep them awaited so the next login doesn't race them.
    await PartnerWidgetManager.clearWidget();
    await SecureTokenStorage.deleteAll();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      prefs.remove(_prefFullName),
      prefs.remove(_prefEmail),
      prefs.remove(_prefMobile),
      prefs.remove(_prefCurrentLat),
      prefs.remove(_prefCurrentLng),
      prefs.remove(_prefCurrentLocationLabel),
      prefs.remove(_prefProfileCompleted),
      prefs.remove(_prefKycCompleted),
      // KYC identity is per-user PII and pre-fills the KYC form. Left behind,
      // bootstrap() reads it back and shows it to whoever logs in next.
      prefs.remove(_prefKycLicenseNo),
      prefs.remove(_prefKycAadharNo),
      prefs.remove(_prefKycPanNo),
      prefs.remove(_prefKycLicenseUrl),
      prefs.remove(_prefKycAadharUrl),
      prefs.remove(_prefKycPanUrl),
      prefs.remove(_prefProfileImagePath),
      prefs.remove(_prefServerProfileImageUrl),
      prefs.remove(_prefDriverName),
      prefs.remove(_prefVehicleName),
      prefs.remove(_prefVehicleLicensePlate),
      prefs.remove(_prefVehicleRawJson),
      prefs.remove(_prefBankDocName),
      prefs.remove(_prefBankAccountName),
      prefs.remove(_prefBankRawJson),
      prefs.remove(_prefActiveOrderId),
      prefs.remove(_prefActiveOrderIds),
      prefs.remove(_prefActiveTripIdsMap),
      prefs.remove(_prefActiveOrdersCache),
      prefs.setBool(_prefRememberMe, false),
      prefs.remove(_prefPermForeground),
      prefs.remove(_prefPermBackground),
      prefs.remove(_prefPermNotification),
      prefs.remove(_prefLicenseRequiresReupload),
      // Per-driver prefs (avg duration, delivered count) are intentionally kept on logout.
      // They are keyed by driver name so other users can't see them,
      // and the same user logging back in the same day needs them intact.
    ]);

    // Server-side cleanup — fire-and-forget so the caller's navigation
    // happens instantly instead of waiting on 2-3 sequential HTTP calls.
    // IMPORTANT: /api/method/logout must run before revoke_token. Otherwise
    // the bearer token is already invalidated on the server and logout
    // responds 401 (no activity-log entry + noisy exception).
    if (accessToRevoke != null && accessToRevoke.isNotEmpty) {
      unawaited(
        _serverCleanupAfterLogout(
          accessToken: accessToRevoke,
          refreshToken: refreshToRevoke,
          tokenType: tokenTypeSnapshot,
        ),
      );
      if (wasOnline)
        unawaited(
          FCMService().unsubscribeWithToken(bearerToken: accessToRevoke),
        );
    }
  }

  /// Sequenced HTTP calls that must happen in order: write the activity-log
  /// entry via /api/method/logout while the bearer is still valid, then
  /// revoke the access and refresh tokens.
  Future<void> _serverCleanupAfterLogout({
    required String accessToken,
    required String? refreshToken,
    required String tokenType,
  }) async {
    await _serverSideLogout(accessToken, tokenType);
    await _revokeTokenOnServer(accessToken);
    if (refreshToken != null &&
        refreshToken.isNotEmpty &&
        refreshToken != accessToken) {
      await _revokeTokenOnServer(refreshToken);
    }
  }

  /// Upload a file to the Driver record via custom upload_kyc_file API.
  /// Returns the Frappe file_url on success, error string prefixed with
  /// 'ERROR:' on failure, or null only on unexpected exceptions.
  Future<String?> uploadFile({
    required String filePath,
    required String fileName,
    String? doctype,
    String? docname,
    String? fieldname,
  }) async {
    if (_sessionToken == null) {
      return null;
    }

    // Build request fields
    final Map<String, String> fields = <String, String>{};
    if (docname != null && docname.isNotEmpty) {
      fields['driver_name'] = docname;
    }
    if (fieldname != null && fieldname.isNotEmpty) {
      fields['fieldname'] = fieldname;
    }
    if (doctype != null && doctype.isNotEmpty) {
      fields['doctype'] = doctype;
    }

    try {
      // Use multi-auth strategy (Bearer token first, then API Key fallback)
      final Map<String, dynamic> payload = await _authorizedUploadFileWithRetry(
        uri: _uploadFileUri,
        filePath: filePath,
        fileName: fileName,
        fields: fields,
      );

      final Map<String, dynamic> data = _extractMethodData(payload);
      return _nullIfBlank(data['file_url']?.toString());
    } catch (_) {
      return null;
    }
  }

  /// Blank the KYC identity fields held in memory.
  ///
  /// These pre-fill the KYC form, so they are per-user PII: anything left here
  /// when the session identity changes surfaces on the next user's KYC page.
  /// Callers are responsible for clearing the matching prefs and notifying.
  void _clearKycIdentity() {
    _existingLicenseNo = null;
    _existingAadharNo = null;
    _existingPanNo = null;
    _existingLicenseUrl = null;
    _existingAadharUrl = null;
    _existingPanUrl = null;
    _existingIssuingDate = null;
    _existingExpiryDate = null;
  }

  /// Submit KYC to create or update the Driver record on ERPNext.
  /// Aadhar fields are required (mandatory on Driver DocType).
  /// driver_name is optional — backend looks up by session user's mobile.
  Future<String?> submitDriverKyc({
    required String aadharNo,
    required String aadharAttachmentUrl,
    String? licenseNumber,
    String? licenseAttachmentUrl,
    String? issuingDate,
    String? expiryDate,
    String? panNo,
    String? panAttachmentUrl,
  }) async {
    if (_sessionToken == null) {
      return 'Not authenticated';
    }

    try {
      final Map<String, String> body = <String, String>{
        'aadhar_no': aadharNo,
        'aadhar_attachment': aadharAttachmentUrl,
      };
      // Pass driver_name if we have one (update), otherwise backend creates
      if (_driverName != null && _driverName!.isNotEmpty) {
        body['driver_name'] = _driverName!;
      }
      if (licenseNumber != null) body['license_number'] = licenseNumber;
      if (licenseAttachmentUrl != null) {
        body['license_attachment'] = licenseAttachmentUrl;
      }
      if (issuingDate != null) body['issuing_date'] = issuingDate;
      if (expiryDate != null) body['expiry_date'] = expiryDate;
      if (panNo != null) body['pan_no'] = panNo;
      if (panAttachmentUrl != null) {
        body['pan_attachment'] = panAttachmentUrl;
      }

      // Use multi-auth strategy (Bearer token first, then API Key fallback)
      final Map<String, dynamic> payload = await _authorizedPostFormWithRetry(
        uri: _submitDriverKycUri,
        body: body,
      );

      final Map<String, dynamic> responseData = _extractMethodData(payload);
      final String status = (responseData['status']?.toString() ?? '')
          .toLowerCase();

      if (status == 'success') {
        // Save driver_name and mark KYC completed
        final String? newDriverName = _nullIfBlank(
          responseData['driver_name']?.toString(),
        );
        if (newDriverName != null) {
          _driverName = newDriverName;
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefDriverName, newDriverName);
        }
        _kycCompleted = true;
        _licenseRequiresReupload = false;
        _existingAadharNo = aadharNo;
        _existingAadharUrl = aadharAttachmentUrl.isNotEmpty
            ? aadharAttachmentUrl
            : _existingAadharUrl;
        _existingLicenseNo = licenseNumber ?? _existingLicenseNo;
        _existingLicenseUrl = licenseAttachmentUrl ?? _existingLicenseUrl;
        _existingPanNo = panNo ?? _existingPanNo;
        _existingPanUrl = panAttachmentUrl ?? _existingPanUrl;
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await Future.wait(<Future<bool>>[
          prefs.setBool(_prefKycCompleted, true),
          if (_existingLicenseNo != null)
            prefs.setString(_prefKycLicenseNo, _existingLicenseNo!),
          if (_existingAadharNo != null)
            prefs.setString(_prefKycAadharNo, _existingAadharNo!),
          if (_existingPanNo != null)
            prefs.setString(_prefKycPanNo, _existingPanNo!),
          if (_existingLicenseUrl != null)
            prefs.setString(_prefKycLicenseUrl, _existingLicenseUrl!),
          if (_existingAadharUrl != null)
            prefs.setString(_prefKycAadharUrl, _existingAadharUrl!),
          if (_existingPanUrl != null)
            prefs.setString(_prefKycPanUrl, _existingPanUrl!),
        ]);
        notifyListeners();
        return null;
      }

      return _extractServerError(payload) ?? 'KYC submission failed';
    } catch (_) {
      return 'Unable to connect. Check internet and try again.';
    }
  }

  Future<void> uploadKycDocument(String key) async {
    if (!_kycStatus.containsKey(key)) {
      return;
    }

    _kycStatus[key] = VerificationStatus.pending;
    _kycProgress[key] = 0.05;
    notifyListeners();

    for (int i = 1; i <= 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      _kycProgress[key] = i / 10;
      notifyListeners();
    }

    _kycStatus[key] = VerificationStatus.pending;
    notifyListeners();
  }

  void _checkLicenseStatus(Map<String, dynamic> driverDoc) {
    if (!_kycCompleted) return;
    final licenseNumber = _nullIfBlank(driverDoc['license_number']?.toString());
    final licenseAttachment = _nullIfBlank(
      driverDoc['custom_license_attachment']?.toString(),
    );
    final removed = licenseNumber == null && licenseAttachment == null;
    if (_licenseRequiresReupload != removed) {
      _licenseRequiresReupload = removed;
      _writePref(
        (SharedPreferences prefs) =>
            prefs.setBool(_prefLicenseRequiresReupload, removed),
      );
      notifyListeners();
    }
  }

  void clearLicenseReuploadFlag() {
    if (_licenseRequiresReupload) {
      _licenseRequiresReupload = false;
      _writePref(
        (SharedPreferences prefs) => prefs.remove(_prefLicenseRequiresReupload),
      );
      notifyListeners();
    }
  }

  Future<String?> resubmitLicense({
    required String licenseNumber,
    required String licenseAttachmentUrl,
    String? issuingDate,
    String? expiryDate,
  }) async {
    if (_sessionToken == null) return 'Not authenticated';

    final String? driverName = _driverName;
    if (driverName == null || driverName.isEmpty) {
      return 'Driver profile not found. Please try again.';
    }

    try {
      final Map<String, dynamic> fields = <String, dynamic>{
        'license_number': licenseNumber,
        'custom_license_attachment': licenseAttachmentUrl,
      };
      if (issuingDate != null) fields['issuing_date'] = issuingDate;
      if (expiryDate != null) fields['expiry_date'] = expiryDate;

      final Uri uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/resource/Driver/${Uri.encodeComponent(driverName)}',
      );

      await authorizedPutJson(uri, fields);
      _licenseRequiresReupload = false;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  void simulateKycApproval() {
    for (final String key in _kycStatus.keys) {
      _kycStatus[key] = VerificationStatus.approved;
      _kycProgress[key] = 1;
    }
    _vehicle = _vehicle == null
        ? null
        : VehicleDetails(
            name: _vehicle!.name,
            licensePlate: _vehicle!.licensePlate,
            make: _vehicle!.make,
            model: _vehicle!.model,
            lastOdometer: _vehicle!.lastOdometer,
            fuelType: _vehicle!.fuelType,
            uom: _vehicle!.uom,
            acquisitionDate: _vehicle!.acquisitionDate,
            location: _vehicle!.location,
            chassisNo: _vehicle!.chassisNo,
            vehicleValue: _vehicle!.vehicleValue,
            employee: _vehicle!.employee,
            insuranceCompany: _vehicle!.insuranceCompany,
            policyNo: _vehicle!.policyNo,
            startDate: _vehicle!.startDate,
            endDate: _vehicle!.endDate,
            carbonCheckDate: _vehicle!.carbonCheckDate,
            color: _vehicle!.color,
            wheels: _vehicle!.wheels,
            doors: _vehicle!.doors,
            status: VerificationStatus.approved,
          );
    _notices.insert(
      0,
      AppNotice(
        title: 'KYC approved',
        message: 'All identity documents are approved by admin.',
        time: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  Future<List<String>> fetchUomOptions() async {
    try {
      final Uri uri = Uri.parse('${ApiConstants.erpBaseUrl}/api/resource/UOM')
          .replace(
            queryParameters: <String, String>{
              'fields': jsonEncode(<String>['name']),
              'limit_page_length': '200',
            },
          );
      final Map<String, dynamic> payload = await _authorizedGet(uri);
      final dynamic data = payload['data'];
      final List<String> values = <String>[];
      if (data is List) {
        for (final dynamic row in data) {
          if (row is Map<String, dynamic>) {
            final String? name = _nullIfBlank(row['name']?.toString());
            if (name != null) {
              values.add(name);
            }
          }
        }
      }
      _uomOptions = values;
      notifyListeners();
      return values;
    } catch (_) {
      return _uomOptions;
    }
  }

  Future<void> fetchVehicleFormConfig() async {
    try {
      final Uri uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/resource/DocType/Vehicle',
      );
      final Map<String, dynamic> payload = await _authorizedGet(uri);
      final dynamic data = payload['data'];
      if (data is! Map<String, dynamic>) {
        return;
      }
      final dynamic fields = data['fields'];
      if (fields is! List) {
        return;
      }

      final Set<String> requiredFields = <String>{};
      List<String> fuelOptions = <String>[];
      for (final dynamic row in fields) {
        if (row is! Map<String, dynamic>) {
          continue;
        }
        final String? fieldname = _nullIfBlank(row['fieldname']?.toString());
        if (fieldname == null) {
          continue;
        }
        final int reqd = int.tryParse(row['reqd']?.toString() ?? '0') ?? 0;
        final int readOnly =
            int.tryParse(row['read_only']?.toString() ?? '0') ?? 0;
        if (reqd == 1 && readOnly == 0) {
          requiredFields.add(fieldname);
        }

        if (fieldname == 'fuel_type') {
          final String? rawOptions = _nullIfBlank(row['options']?.toString());
          if (rawOptions != null) {
            fuelOptions = rawOptions
                .split('\n')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList();
          }
        }
      }
      _vehicleRequiredFields = requiredFields;
      _vehicleFuelOptions = fuelOptions;
      notifyListeners();
    } catch (_) {
      // Keep existing cached config
    }
  }

  Future<Map<String, dynamic>?> fetchVehicleByLicensePlate(
    String licensePlate,
  ) async {
    final String plate = licensePlate.trim().toUpperCase();
    if (plate.isEmpty) {
      return null;
    }

    final String? name = await _findResourceName(
      doctype: 'Vehicle',
      filters: <List<String>>[
        <String>['Vehicle', 'license_plate', '=', plate],
      ],
      fields: <String>['name'],
    );
    if (name == null) {
      return null;
    }
    return _fetchResourceDoc('Vehicle', name);
  }

  Future<Map<String, dynamic>?> fetchVehicleByName(String vehicleName) async {
    final String? name = _nullIfBlank(vehicleName);
    if (name == null) {
      return null;
    }
    return _fetchResourceDoc('Vehicle', name);
  }

  Future<void> hydrateVehicleFromBackend({bool forceRefresh = false}) async {
    if (!forceRefresh && _vehicle != null) {
      return;
    }
    if (_sessionToken == null || _sessionToken!.isEmpty) {
      return;
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? vehicleName = _nullIfBlank(
        prefs.getString(_prefVehicleName),
      );
      final String? licensePlate = _nullIfBlank(
        prefs.getString(_prefVehicleLicensePlate),
      );

      Map<String, dynamic>? data;
      if (vehicleName != null) {
        data = await fetchVehicleByName(vehicleName);
      }
      if (data == null && licensePlate != null) {
        data = await fetchVehicleByLicensePlate(licensePlate);
      }
      // Fallback: vehicle linked directly in driver profile doc
      if (data == null) {
        final String? vehicleFromDriver = _nullIfBlank(
          _loggedProfileDetails?.driver?['vehicle']?.toString(),
        );
        if (vehicleFromDriver != null) {
          data = await fetchVehicleByName(vehicleFromDriver);
        }
      }
      // Final fallback: search Vehicle doctype by the driver's employee id.
      // Catches cases where SharedPreferences were cleared and the Driver doc
      // has no vehicle field set, but the Vehicle doc still has employee set.
      if (data == null) {
        final String? employeeFromDriver = _nullIfBlank(
          _loggedProfileDetails?.driver?['employee']?.toString(),
        );
        if (employeeFromDriver != null) {
          final String? nameByEmployee = await _findResourceName(
            doctype: 'Vehicle',
            filters: <List<String>>[
              <String>['Vehicle', 'employee', '=', employeeFromDriver],
            ],
          );
          if (nameByEmployee != null) {
            data = await fetchVehicleByName(nameByEmployee);
          }
        }
      }
      if (data == null) {
        return;
      }

      _submittedVehicleRaw = data;
      _vehicle = _vehicleFromApiData(data);
      final SharedPreferences vehicleHydratePrefs =
          await SharedPreferences.getInstance();
      await vehicleHydratePrefs.setString(
        _prefVehicleRawJson,
        jsonEncode(data),
      );
      notifyListeners();
    } catch (_) {
      // Ignore hydration failures; screen stays editable.
    }
  }

  Future<List<String>> fetchVehicleEmployeeOptions({String query = ''}) async {
    return _fetchDocListOptions(
      doctype: 'Employee',
      searchFields: const <String>['name', 'employee_name'],
      query: query,
      pageLength: 10,
    );
  }

  Future<List<String>> fetchLinkOptions({
    required String doctype,
    String referenceDoctype = 'Bank Account',
    String query = '',
    int pageLength = 10,
    Map<String, dynamic>? filters,
  }) async {
    // Convert {field: value} map to [[field, '=', value], ...] list format
    // that frappe.client.get_list expects.
    final List<List<dynamic>> filterList = <List<dynamic>>[];
    if (filters != null) {
      filters.forEach((String field, dynamic value) {
        filterList.add(<dynamic>[field, '=', value]);
      });
    }
    return _fetchDocListOptions(
      doctype: doctype,
      query: query,
      pageLength: pageLength,
      extraFilters: filterList,
    );
  }

  /// Replaces `frappe.desk.search.search_link` (which requires Desk access)
  /// with `frappe.client.get_list`, accessible to non-desk partner users.
  Future<List<String>> _fetchDocListOptions({
    required String doctype,
    String query = '',
    int pageLength = 10,
    List<String> searchFields = const <String>['name'],
    List<List<dynamic>> extraFilters = const <List<dynamic>>[],
  }) async {
    try {
      // Build filters: name/search-field LIKE '%query%' + any extra filters.
      final List<List<dynamic>> filterList = <List<dynamic>>[...extraFilters];
      final String trimmed = query.trim();
      if (trimmed.isNotEmpty) {
        // Search across all provided search fields (OR logic via OR operator).
        // frappe.client.get_list only supports AND between top-level filters,
        // so we search on 'name' which is the primary key and always works.
        filterList.add(<dynamic>['name', 'like', '%$trimmed%']);
      }

      final Map<String, String> queryParams = <String, String>{
        'doctype': doctype,
        'fields': jsonEncode(searchFields),
        'limit_page_length': '$pageLength',
        'limit_start': '0',
        'order_by': 'name asc',
      };
      if (filterList.isNotEmpty) {
        queryParams['filters'] = jsonEncode(filterList);
      }

      final Uri uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/method/frappe.client.get_list',
      ).replace(queryParameters: queryParams);

      final Map<String, dynamic> payload = await _authorizedGet(uri);

      final dynamic responseRows =
          payload['message'] ?? payload['data'] ?? payload['results'];
      if (responseRows is! List) {
        return <String>[];
      }

      final List<String> values = <String>[];
      for (final dynamic item in responseRows) {
        String? value;
        if (item is Map<String, dynamic>) {
          // Prefer the first search field, fall back to 'name'.
          for (final String field in searchFields) {
            value = _nullIfBlank(item[field]?.toString());
            if (value != null) break;
          }
          value ??= _nullIfBlank(item['name']?.toString());
        } else if (item is String) {
          value = _nullIfBlank(item);
        }
        if (value != null && !values.contains(value)) {
          values.add(value);
        }
      }

      return values;
    } catch (_) {
      return <String>[];
    }
  }

  Future<Map<String, String>> fetchBankAccountLinkDoctypes() async {
    try {
      final Uri uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/resource/DocType/Bank%20Account',
      );
      final Map<String, dynamic> payload = await _authorizedGet(uri);
      final dynamic data = payload['data'];
      if (data is! Map<String, dynamic>) {
        return <String, String>{};
      }
      final dynamic fields = data['fields'];
      if (fields is! List) {
        return <String, String>{};
      }

      final Map<String, String> doctypesByField = <String, String>{};
      for (final dynamic row in fields) {
        if (row is! Map<String, dynamic>) {
          continue;
        }
        final String? fieldname = _nullIfBlank(row['fieldname']?.toString());
        final String? fieldtype = _nullIfBlank(row['fieldtype']?.toString());
        final String? options = _nullIfBlank(row['options']?.toString());
        if (fieldname == null || fieldtype == null || options == null) {
          continue;
        }
        if (fieldtype == 'Link' || fieldtype == 'Dynamic Link') {
          doctypesByField[fieldname] = options;
        }
      }
      return doctypesByField;
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> hydrateBankFromBackend({bool forceRefresh = false}) async {
    if (!forceRefresh && _bank != null) {
      return;
    }
    if (_sessionToken == null || _sessionToken!.isEmpty) {
      return;
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? bankDocName = _nullIfBlank(
        prefs.getString(_prefBankDocName),
      );
      final String? accountName = _nullIfBlank(
        prefs.getString(_prefBankAccountName),
      );

      Map<String, dynamic>? data;
      if (bankDocName != null) {
        data = await _fetchResourceDoc('Bank Account', bankDocName);
      }
      if (data == null && accountName != null) {
        final String? name = await _findResourceName(
          doctype: 'Bank Account',
          filters: <List<String>>[
            <String>['Bank Account', 'account_name', '=', accountName],
          ],
          fields: <String>['name'],
        );
        if (name != null) {
          data = await _fetchResourceDoc('Bank Account', name);
        }
      }
      // Fallback: search by driver as party
      if (data == null && _driverName != null) {
        final String? name = await _findResourceName(
          doctype: 'Bank Account',
          filters: <List<String>>[
            <String>['Bank Account', 'party_type', '=', 'Driver'],
            <String>['Bank Account', 'party', '=', _driverName!],
          ],
          fields: <String>['name'],
        );
        if (name != null) {
          data = await _fetchResourceDoc('Bank Account', name);
        }
      }
      if (data == null) {
        return;
      }

      _submittedBankRaw = data;
      _bank = _bankFromApiData(data);
      final SharedPreferences hydratePrefs =
          await SharedPreferences.getInstance();
      await hydratePrefs.setString(_prefBankRawJson, jsonEncode(data));
      notifyListeners();
    } catch (_) {
      // Ignore hydration failures; screen stays editable.
    }
  }

  Future<VehicleSubmitResult> submitVehicleDetails({
    required String licensePlate,
    required String make,
    required String model,
    required String lastOdometer,
    required String fuelType,
    required String uom,
    String? acquisitionDate,
    String? location,
    String? chassisNo,
    String? vehicleValue,
    String? employee,
    String? insuranceCompany,
    String? policyNo,
    String? startDate,
    String? endDate,
    String? carbonCheckDate,
    String? color,
    String? wheels,
    String? doors,
  }) async {
    if (_vehicleRequiredFields.isEmpty || _vehicleFuelOptions.isEmpty) {
      await fetchVehicleFormConfig();
    }

    bool isRequired(String fieldname) {
      return _vehicleRequiredFields.contains(fieldname);
    }

    final String plate = licensePlate.trim().toUpperCase();
    if (isRequired('license_plate') && plate.isEmpty) {
      return const VehicleSubmitResult(error: 'License plate is required');
    }
    if (isRequired('make') && make.trim().isEmpty) {
      return const VehicleSubmitResult(error: 'Make is required');
    }
    if (isRequired('model') && model.trim().isEmpty) {
      return const VehicleSubmitResult(error: 'Model is required');
    }
    final int? odometer = int.tryParse(lastOdometer.trim());
    if (isRequired('last_odometer') && (odometer == null || odometer < 0)) {
      return const VehicleSubmitResult(
        error: 'Odometer value must be a valid non-negative number',
      );
    }
    final String fuel = fuelType.trim();
    if (isRequired('fuel_type') && fuel.isEmpty) {
      return const VehicleSubmitResult(error: 'Fuel type is required');
    }
    if (_vehicleFuelOptions.isNotEmpty && !_vehicleFuelOptions.contains(fuel)) {
      return const VehicleSubmitResult(error: 'Select a valid fuel type');
    }
    final String uomValue = uom.trim();
    if (isRequired('uom') && uomValue.isEmpty) {
      return const VehicleSubmitResult(error: 'Fuel UOM is required');
    }

    final int? wheelsInt = _nullableInt(wheels);
    if (wheels?.trim().isNotEmpty == true && wheelsInt == null) {
      return const VehicleSubmitResult(error: 'Wheels must be a valid number');
    }
    final int? doorsInt = _nullableInt(doors);
    if (doors?.trim().isNotEmpty == true && doorsInt == null) {
      return const VehicleSubmitResult(error: 'Doors must be a valid number');
    }
    final double? vehicleValueDouble = _nullableDouble(vehicleValue);
    if (vehicleValue?.trim().isNotEmpty == true && vehicleValueDouble == null) {
      return const VehicleSubmitResult(
        error: 'Vehicle value must be a valid number',
      );
    }

    final String? defaultEmployee = _nullIfBlank(
      _loggedProfileDetails?.driver?['employee']?.toString(),
    );
    final String? employeeValue = _nullIfBlank(employee) ?? defaultEmployee;

    final String? acquisitionDateValue = _nullIfBlank(acquisitionDate);
    final String? locationValue = _nullIfBlank(location);
    final String? chassisNoValue = _nullIfBlank(chassisNo);
    final String? insuranceCompanyValue = _nullIfBlank(insuranceCompany);
    final String? policyNoValue = _nullIfBlank(policyNo);
    final String? startDateValue = _nullIfBlank(startDate);
    final String? endDateValue = _nullIfBlank(endDate);
    final String? carbonCheckDateValue = _nullIfBlank(carbonCheckDate);
    final String? colorValue = _nullIfBlank(color);

    final Map<String, dynamic> body = <String, dynamic>{
      'license_plate': plate,
      'make': make.trim(),
      'model': model.trim(),
      'last_odometer': odometer,
      'fuel_type': fuel,
      'uom': uomValue,
    };
    if (acquisitionDateValue != null) {
      body['acquisition_date'] = acquisitionDateValue;
    }
    if (locationValue != null) {
      body['location'] = locationValue;
    }
    if (chassisNoValue != null) {
      body['chassis_no'] = chassisNoValue;
    }
    if (vehicleValueDouble != null) {
      body['vehicle_value'] = vehicleValueDouble;
    }
    if (employeeValue != null) {
      body['employee'] = employeeValue;
    }
    if (insuranceCompanyValue != null) {
      body['insurance_company'] = insuranceCompanyValue;
    }
    if (policyNoValue != null) {
      body['policy_no'] = policyNoValue;
    }
    if (startDateValue != null) {
      body['start_date'] = startDateValue;
    }
    if (endDateValue != null) {
      body['end_date'] = endDateValue;
    }
    if (carbonCheckDateValue != null) {
      body['carbon_check_date'] = carbonCheckDateValue;
    }
    if (colorValue != null) {
      body['color'] = colorValue;
    }
    if (wheelsInt != null) {
      body['wheels'] = wheelsInt;
    }
    if (doorsInt != null) {
      body['doors'] = doorsInt;
    }

    try {
      final Uri baseUri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/resource/Vehicle',
      );
      final Map<String, dynamic>? existing = await fetchVehicleByLicensePlate(
        plate,
      );
      final String? vehicleName = _nullIfBlank(existing?['name']?.toString());
      Map<String, dynamic> responsePayload;
      final bool wasUpdate = vehicleName != null;

      if (vehicleName != null) {
        final Uri updateUri = Uri.parse(
          '${ApiConstants.erpBaseUrl}/api/resource/Vehicle/${Uri.encodeComponent(vehicleName)}',
        );
        responsePayload = await authorizedPutJson(updateUri, body);
      } else {
        responsePayload = await _authorizedPostJson(baseUri, body);
      }

      final dynamic rawData = responsePayload['data'];
      final Map<String, dynamic> data = rawData is Map<String, dynamic>
          ? rawData
          : body;
      final String? finalName =
          _nullIfBlank(data['name']?.toString()) ?? vehicleName;
      final Map<String, dynamic>? fetched = await fetchVehicleByName(
        finalName ?? '',
      );
      final Map<String, dynamic> finalData = fetched ?? data;
      _submittedVehicleRaw = finalData;
      _vehicle = _vehicleFromApiData(finalData);
      await _persistVehicleIdentity(
        vehicleName: _nullIfBlank(finalData['name']?.toString()) ?? finalName,
        licensePlate: plate,
      );
      final SharedPreferences vehicleSubmitPrefs =
          await SharedPreferences.getInstance();
      await vehicleSubmitPrefs.setString(
        _prefVehicleRawJson,
        jsonEncode(finalData),
      );
      // Keep Driver.vehicle in sync so the Driver doc is the source of truth
      // for vehicle identity after logout (SharedPreferences are cleared).
      if (finalName != null) {
        try {
          await _setDriverField('vehicle', finalName);
        } catch (_) {
        }
      }
      notifyListeners();
      return VehicleSubmitResult(
        vehicleName: finalName,
        vehicleData: finalData,
        wasUpdate: wasUpdate,
      );
    } catch (e) {
      return VehicleSubmitResult(
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<String?> submitBankDetails({
    required String accountName,
    required String bank,
    String? accountType,
    String? accountSubtype,
    bool disabled = false,
    bool isDefault = false,
    bool isCompanyAccount = false,
    String? company,
    String? partyType,
    String? party,
    String? iban,
    String? branchCode,
    String? branchName,
    String? bankAccountNo,
    String? confirmAccountNo,
    String? lastIntegrationDate,
  }) async {
    final String normalizedAccountName = accountName.trim();
    if (normalizedAccountName.isEmpty) {
      return 'Account name is required';
    }
    final String normalizedBank = bank.trim();
    if (normalizedBank.isEmpty) {
      return 'Bank is required';
    }
    if (disabled && isDefault) {
      return 'Disabled account cannot be marked as default';
    }

    final String? normalizedAccountType = _nullIfBlank(accountType);
    final String? normalizedAccountSubtype = _nullIfBlank(accountSubtype);
    final String? normalizedCompany = _nullIfBlank(company);
    final String? normalizedPartyType = _nullIfBlank(partyType);
    final String? normalizedParty = _nullIfBlank(party);
    final String? normalizedBranchCode = _nullIfBlank(branchCode);
    final String? normalizedBranchName = _nullIfBlank(branchName);
    final String? normalizedBankAccountNo = _nullIfBlank(bankAccountNo);
    final String? normalizedConfirmAccountNo = _nullIfBlank(confirmAccountNo);
    final String? normalizedLastIntegrationDate = _nullIfBlank(
      lastIntegrationDate,
    );

    if (isCompanyAccount && normalizedCompany == null) {
      return 'Company is required when company account is enabled';
    }
    if ((normalizedPartyType == null) != (normalizedParty == null)) {
      return 'Select both Party Type and Party';
    }
    if (normalizedLastIntegrationDate != null &&
        DateTime.tryParse(normalizedLastIntegrationDate) == null) {
      return 'Last integration date must be in YYYY-MM-DD format';
    }
    if (normalizedBranchCode == null) {
      return 'Branch code is required';
    }
    if (!RegExp(
      r'^[A-Z]{4}0[A-Z0-9]{6}$',
    ).hasMatch(normalizedBranchCode.toUpperCase())) {
      return 'Enter a valid IFSC code (e.g. SBIN0001234)';
    }
    if (normalizedBankAccountNo != null &&
        !RegExp(r'^\d{9,18}$').hasMatch(normalizedBankAccountNo)) {
      return 'Enter a valid account number (9–18 digits)';
    }

    String? normalizedIban = _nullIfBlank(iban);
    if (normalizedIban != null) {
      normalizedIban = normalizedIban.replaceAll(' ', '').toUpperCase();
      if (!RegExp(r'^[A-Z0-9]{8,34}$').hasMatch(normalizedIban)) {
        return 'IBAN format is invalid';
      }
    }

    final Map<String, dynamic> body = <String, dynamic>{
      'account_name': normalizedAccountName,
      'bank': normalizedBank,
    };
    if (normalizedAccountType != null) {
      body['account_type'] = normalizedAccountType;
    }
    if (normalizedAccountSubtype != null) {
      body['account_subtype'] = normalizedAccountSubtype;
    }
    if (normalizedCompany != null) {
      body['company'] = normalizedCompany;
    }
    if (normalizedPartyType != null) {
      body['party_type'] = normalizedPartyType;
    }
    if (normalizedParty != null) {
      body['party'] = normalizedParty;
    }
    if (normalizedIban != null) {
      body['iban'] = normalizedIban;
    }
    body['branch_code'] = normalizedBranchCode.toUpperCase();
    if (normalizedBranchName != null) {
      body['branch_name'] = normalizedBranchName;
    }
    if (normalizedBankAccountNo != null) {
      body['bank_account_no'] = normalizedBankAccountNo.toUpperCase();
    }
    if (normalizedConfirmAccountNo != null) {
      body['confirm_account_no'] = normalizedConfirmAccountNo.toUpperCase();
    }
    if (normalizedLastIntegrationDate != null) {
      body['last_integration_date'] = normalizedLastIntegrationDate;
    }

    try {
      Map<String, dynamic>? responsePayload;
      final String? existingName = await _findResourceName(
        doctype: 'Bank Account',
        filters: <List<String>>[
          <String>['Bank Account', 'account_name', '=', normalizedAccountName],
        ],
        fields: <String>['name'],
      );
      if (existingName != null) {
        final Uri updateUri = Uri.parse(
          '${ApiConstants.erpBaseUrl}/api/resource/Bank%20Account/${Uri.encodeComponent(existingName)}',
        );
        responsePayload = await authorizedPutJson(updateUri, body);
      } else {
        final Uri createUri = Uri.parse(
          '${ApiConstants.erpBaseUrl}/api/resource/Bank%20Account',
        );
        responsePayload = await _authorizedPostJson(createUri, body);
      }

      final dynamic responseData = responsePayload['data'];
      final Map<String, dynamic>? raw = responseData is Map<String, dynamic>
          ? responseData
          : null;
      final String? bankName =
          _nullIfBlank(raw?['name']?.toString()) ?? existingName;
      if (bankName != null) {
        final Map<String, dynamic>? fetched = await _fetchResourceDoc(
          'Bank Account',
          bankName,
        );
        _submittedBankRaw = fetched ?? raw;
      } else {
        _submittedBankRaw = raw;
      }

      _bank = BankDetails(
        accountNumber: normalizedBankAccountNo ?? normalizedAccountName,
        ifsc: normalizedBranchCode.toUpperCase(),
        accountHolder: normalizedAccountName,
        upiId: normalizedIban,
        verified: true,
      );
      final String? resolvedBankName =
          _nullIfBlank(_submittedBankRaw?['name']?.toString()) ?? bankName;
      await _persistBankIdentity(
        bankDocName: resolvedBankName,
        accountName: normalizedAccountName,
      );
      // Keep Driver.custom_bank_account in sync so the Driver doc is the
      // source of truth for bank identity after logout (SharedPreferences
      // are cleared). Uses custom_ prefix — Frappe adds it to all fields
      // created via Customize Form (unlike 'vehicle' which is a standard field).
      if (resolvedBankName != null) {
        try {
          await _setDriverField('custom_bank_account', resolvedBankName);
        } catch (_) {
        }
      }
      if (_submittedBankRaw != null) {
        final SharedPreferences submitPrefs =
            await SharedPreferences.getInstance();
        await submitPrefs.setString(
          _prefBankRawJson,
          jsonEncode(_submittedBankRaw),
        );
      }
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  void setPermissionState({
    bool? foreground,
    bool? background,
    bool? notification,
  }) {
    _permissionState = _permissionState.copyWith(
      foregroundLocation: foreground,
      backgroundLocation: background,
      notification: notification,
    );
    if (foreground != null) {
      _writePref(
        (SharedPreferences prefs) =>
            prefs.setBool(_prefPermForeground, foreground),
      );
    }
    if (background != null) {
      _writePref(
        (SharedPreferences prefs) =>
            prefs.setBool(_prefPermBackground, background),
      );
    }
    if (notification != null) {
      _writePref(
        (SharedPreferences prefs) =>
            prefs.setBool(_prefPermNotification, notification),
      );
    }
    notifyListeners();
  }

  Future<void> syncPermissionsFromOS() async {
    final locationPerm = await Geolocator.checkPermission();
    final notifStatus = await ph.Permission.notification.status;

    final foreground =
        locationPerm == LocationPermission.whileInUse ||
        locationPerm == LocationPermission.always;
    final background = locationPerm == LocationPermission.always;
    final notification = notifStatus.isGranted;

    _permissionState = PermissionState(
      foregroundLocation: foreground,
      backgroundLocation: background,
      notification: notification,
    );
    notifyListeners();
  }

  void setTrackingInterval(int seconds) {
    _trackingInterval = seconds;
    notifyListeners();
  }

  Future<String?> setOnline(bool value) async {
    if (value && !canGoOnline) {
      final List<String> missing = [];
      if (!_kycCompleted) missing.add('KYC submission');
      if (_vehicle == null) missing.add('vehicle details');
      if (!(_bank?.verified ?? false)) missing.add('bank setup');
      if (!hasSelectedLocation) missing.add('location selection');
      if (!_permissionState.allGranted) missing.add('app permissions');
      return 'Please complete: ${missing.join(', ')}';
    }

    if (_availabilitySyncing) return null;
    if (_isOnline == value) return null;

    _availabilitySyncing = true;
    final bool previous = _isOnline;
    _isOnline = value;
    notifyListeners();

    final String? syncError = await _syncAvailabilityToBackend(value);
    if (syncError != null) {
      if (value) {
        // Going Online: if the backend never recorded us online, we won't be
        // assigned orders anyway — so don't show a misleading Online state.
        // Roll back to the previous state and surface the error.
        _isOnline = previous;
        _availabilitySyncing = false;
        notifyListeners();
        return syncError;
      }
      // Going Offline is safety-critical: the driver asked to stop receiving
      // work. We MUST stay Offline locally even though the backend write
      // failed — never revert to Online. Persist it, run the offline
      // side-effects below, and retry the backend write in the background so
      // the server's flag eventually matches.
      debugPrint('[Availability] Offline sync failed, staying offline: $syncError');
      _retryOfflineSyncInBackground();
    }

    _writePref((SharedPreferences prefs) {
      return prefs.setBool(_prefIsOnline, _isOnline);
    });
    if (_isOnline) {
      _onlineSince = DateTime.now();
      startTracking();
      recordTimingEvent(eventType: TimingEventType.login);
      unawaited(FCMService().subscribe(this));
      _notices.insert(
        0,
        AppNotice(
          title: 'You are online',
          message: 'Nearby orders will now be assigned to you.',
          time: DateTime.now(),
        ),
      );
    } else {
      if (_onlineSince != null) {
        final session = DateTime.now().difference(_onlineSince!);
        if (!session.isNegative) _completedDutyToday += session;
      }
      _onlineSince = null;
      stopTracking();
      recordTimingEvent(eventType: TimingEventType.logout);
      unawaited(FCMService().unsubscribe(this));
      // Clear any order alerts still sitting in the tray so an Offline
      // driver can neither see nor tap through to a new order.
      unawaited(FCMInitializer().clearNotifications());
    }

    PartnerWidgetManager.updateWidget(
      isOnline: _isOnline,
      todayEarnings: _earnings.today,
      activeOrder: activeOrder,
    );

    _availabilitySyncing = false;
    notifyListeners();
    return null;
  }

  Future<String?> _syncAvailabilityToBackend(bool value) async {
    if (_driverName == null || _driverName!.trim().isEmpty) {
      return null; // No driver record yet — skip backend sync silently
    }
    try {
      final Uri uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/resource/Driver/${Uri.encodeComponent(_driverName!)}',
      );
      await authorizedPutJson(uri, <String, dynamic>{
        'custom_custom_is_online': value ? 1 : 0,
      });
      return null;
    } catch (e) {
      return 'Failed to sync availability: ${e.toString().replaceAll('Exception: ', '')}';
    }
  }

  /// Best-effort background retry of the "go Offline" backend write. Used when
  /// the driver toggles Offline but the network call fails: we keep them
  /// Offline locally (never revert to Online) and re-attempt so the server's
  /// availability flag eventually matches. Aborts if the driver goes back
  /// Online in the meantime, since that toggle supersedes this one.
  void _retryOfflineSyncInBackground() {
    unawaited(() async {
      for (int attempt = 1; attempt <= 3; attempt++) {
        await Future.delayed(Duration(seconds: 5 * attempt));
        if (_isOnline) return; // a later toggle to Online supersedes this
        final String? err = await _syncAvailabilityToBackend(false);
        if (err == null) {
          debugPrint('[Availability] Offline re-sync succeeded (attempt $attempt)');
          return;
        }
        debugPrint('[Availability] Offline re-sync failed (attempt $attempt): $err');
      }
    }());
  }

  Future<String?> startTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Location services are disabled. Please enable GPS.';
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return 'Location permission denied.';
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return 'Location permissions are permanently denied.';
    }

    _isTracking = true;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((Position position) {
          _currentLatitude = position.latitude;
          _currentLongitude = position.longitude;
          _liveCoordinates =
              '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
          notifyListeners();
        });

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _currentLatitude = position.latitude;
      _currentLongitude = position.longitude;
      _liveCoordinates =
          '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
    } catch (_) {
    }

    notifyListeners();
    return null;
  }

  /// Seeds the partner's current location with a single GPS fix when it isn't
  /// already known. Used by screens (e.g. Orders by Location) that need an
  /// origin point for the delivery-radius filter but don't start continuous
  /// tracking. Returns true when a location is available afterwards (either it
  /// was already set, or it was just fetched); false when it couldn't be
  /// obtained (service off, permission denied, or fetch failure) so the caller
  /// can fail open.
  Future<bool> ensureCurrentLocation() async {
    if (_currentLatitude != null && _currentLongitude != null) {
      return true;
    }
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _currentLatitude = position.latitude;
      _currentLongitude = position.longitude;
      _liveCoordinates =
          '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
    notifyListeners();
  }

  void tickLocation() {
    if (!_isTracking) {
      return;
    }
    final lat = _currentLatitude;
    final lng = _currentLongitude;
    if (lat != null && lng != null) {
      // Route every tick through the offline queue. Online: it flushes
      // immediately. Offline: it persists to Hive and drains on reconnect.
      unawaited(SyncManager().queueLocationPing(lat, lng));
    }
    notifyListeners();
  }

  void respondToOrderRequest({required bool accept}) {
    if (_incomingOrder == null) {
      return;
    }

    if (accept) {
      final incoming = _incomingOrder;
      if (incoming != null &&
          _activeOrders.length < maxConcurrentOrders &&
          !_activeOrders.any((o) => o.orderId == incoming.orderId)) {
        _activeOrders.add(incoming);
        _currentlyViewedOrderIndex = _activeOrders.length - 1;
        unawaited(_persistActiveOrders());
      }
      _performance = _performance.copyWith(
        acceptanceRate: min(100, _performance.acceptanceRate + 0.8),
      );
    } else {
      _performance = _performance.copyWith(
        acceptanceRate: max(0, _performance.acceptanceRate - 1.2),
      );
      _notices.insert(
        0,
        AppNotice(
          title: 'Order skipped',
          message: 'No response received. Acceptance score updated.',
          time: DateTime.now(),
        ),
      );
    }
    _incomingOrder = null;

    PartnerWidgetManager.updateWidget(
      isOnline: _isOnline,
      todayEarnings: _earnings.today,
      activeOrder: activeOrder,
    );

    notifyListeners();
  }

  Future<String?> updateOrderStatus(
    OrderProgressStatus status, {
    String? orderId,
  }) async {
    // NOTE: availability (Online/Offline) is intentionally NOT checked here.
    // Advancing/completing an already-accepted order is committed work and
    // must succeed even when the driver is Offline (industry-standard: Offline
    // only blocks NEW work, not finishing in-progress trips). Network-offline
    // completion is handled separately by OfflineTripManager's sync queue.
    final String? targetId = orderId ?? activeOrder?.orderId;
    if (targetId == null) return 'No active order found';

    final int idx = _activeOrders.indexWhere((o) => o.orderId == targetId);
    if (idx == -1) return 'Order not found in active orders';

    final DeliveryOrder targetOrder = _activeOrders[idx];
    final String? targetTripId = _activeTripIds[targetId];

    try {
      final String? frappeStatus = _toFrappeStatus(status);
      if (frappeStatus != null) {
        try {
          await _orderRepository.updateStatusViaSetValue(
            targetId,
            frappeStatus,
          );
        } catch (_) {
        }
      }

      if (targetTripId != null) {
        final String? stopStatus = _toTripStopStatus(status);
        if (stopStatus != null) {
          try {
            await _orderRepository.updateTripStopStatusByDelivery(
              tripId: targetTripId,
              deliveryId: targetId,
              newStatus: stopStatus,
            );
          } catch (_) {
          }
        }
      }

      final DeliveryOrder updated = targetOrder.copyWith(
        orderStatus: status,
        assignmentStatus: OrderAssignmentStatus.assigned,
        reachedStoreAt: status == OrderStatus.reachedPickup
            ? DateTime.now()
            : targetOrder.reachedStoreAt,
        deliveryPartnerLocation: status == OrderStatus.reachedPickup
            ? _partnerLiveLocation ??
                  GeoLocation(
                    latitude: _currentLatitude ?? 28.6139,
                    longitude: _currentLongitude ?? 77.2090,
                  )
            : targetOrder.deliveryPartnerLocation,
      );
      _activeOrders[idx] = updated;
      _replaceAcceptedOrder(updated);

      if (status == OrderStatus.delivered) {
        final double payout = updated.estimatedEarnings;
        _earnings = _earnings.copyWith(
          today: _earnings.today + payout,
          week: _earnings.week + payout,
          total: _earnings.total + payout,
          pendingPayout: _earnings.pendingPayout + payout,
        );
        _performance = _performance.copyWith(
          completionRate: min(100, _performance.completionRate + 0.2),
          totalDeliveries: _performance.totalDeliveries + 1,
        );
        _notices.insert(
          0,
          AppNotice(
            title: 'Delivery completed',
            message: 'Order $targetId delivered successfully.',
            time: DateTime.now(),
          ),
        );
        recordTimingEvent(
          eventType: TimingEventType.tripCompleted,
          tripRef: targetId,
        );
        _acceptedOrders.removeWhere((order) => order.orderId == targetId);
        clearOrder(targetId);
      } else if (status == OrderStatus.reachedPickup) {
        _notices.insert(
          0,
          AppNotice(
            title: 'Store Notified',
            message: 'Store has been informed that you have arrived.',
            time: DateTime.now(),
          ),
        );
        unawaited(_persistActiveOrders());
      } else {
        unawaited(_persistActiveOrders());
      }

      PartnerWidgetManager.updateWidget(
        isOnline: _isOnline,
        todayEarnings: _earnings.today,
        activeOrder: activeOrder,
      );
      notifyListeners();
      if (status == OrderStatus.reachedPickup) {
        _writeTimingEvent(
          eventType: TimingEventType.pickupReached,
          tripRef: targetTripId,
        );
      } else if (status == OrderStatus.pickedUp) {
        _writeTimingEvent(
          eventType: TimingEventType.pickedUp,
          tripRef: targetTripId,
        );
      }
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  Future<String?> failDelivery({
    required String orderId,
    required String reason,
    String? reasonCode,
    String? photoPath,
    bool shouldCreateReturnTrip = false,
  }) async {
    final String? tripId = _activeTripIds[orderId];
    String? syncError;
    try {
      if (tripId != null) {
        await _orderRepository.processFailedDeliveryReturnByIds(
          tripId: tripId,
          deliveryId: orderId,
          reason: reason,
          reasonCode: reasonCode,
          photoPath: photoPath,
          shouldCreateReturnTrip: shouldCreateReturnTrip,
        );
      } else {
        await _orderRepository.updateStatusViaSetValue(orderId, 'Failed');
        if (photoPath != null && photoPath.isNotEmpty) {
          await _orderRepository.uploadProofPhoto(
            orderName: orderId,
            filePath: photoPath,
          );
        }
      }
    } catch (e) {
      syncError = e.toString().replaceFirst('Exception: ', '');
    }
    _writeTimingEvent(eventType: TimingEventType.stopFailed, tripRef: tripId);
    _notices.insert(
      0,
      AppNotice(
        title: 'Delivery failed',
        message: 'Order $orderId marked as failed.',
        time: DateTime.now(),
      ),
    );
    clearOrder(orderId);
    return syncError;
  }

  void clearOrder(String orderId) {
    _activeOrders.removeWhere((o) => o.orderId == orderId);
    _activeTripIds.remove(orderId);
    _currentlyViewedOrderIndex = _currentlyViewedOrderIndex.clamp(
      0,
      _activeOrders.isEmpty ? 0 : _activeOrders.length - 1,
    );
    if (_activeOrders.isEmpty) {
      _locationPingSubscription?.cancel();
      _locationPingSubscription = null;
      LocationPingService.stop();
    }
    unawaited(_persistActiveOrders());
    unawaited(
      PartnerWidgetManager.updateWidget(
        isOnline: _isOnline,
        todayEarnings: _earnings.today,
        activeOrder: activeOrder,
      ),
    );
    notifyListeners();
  }

  void clearActiveOrder() => clearOrder(activeOrder?.orderId ?? '');

  void setViewedOrderIndex(int index) {
    if (_activeOrders.isEmpty) return;
    final clamped = index.clamp(0, _activeOrders.length - 1);
    if (clamped == _currentlyViewedOrderIndex) return;
    _currentlyViewedOrderIndex = clamped;
    notifyListeners();
  }

  List<DeliveryOrder> get availableOrders =>
      List<DeliveryOrder>.unmodifiable(_availableOrders);

  List<DeliveryOrder> get acceptedOrders =>
      List<DeliveryOrder>.unmodifiable(_acceptedOrders);

  bool get isLoadingOrders => _isLoadingOrders;

  String? get orderLoadingError => _orderLoadingError;

  bool get isFetchingActiveOrder => _isFetchingActiveOrder;

  GeoLocation? get partnerLiveLocation => _partnerLiveLocation;

  Future<void> fetchAvailableOrders() async {
    _isLoadingOrders = true;
    _orderLoadingError = null;
    notifyListeners();

    try {
      final List<ExternalDelivery> summaries = await _orderRepository
          .fetchAllByStatus('Pending');
      final List<DeliveryOrder> orders = <DeliveryOrder>[];

      const int batchSize = 6;
      for (int index = 0; index < summaries.length; index += batchSize) {
        final List<ExternalDelivery> batch = summaries
            .skip(index)
            .take(batchSize)
            .toList();
        final List<DeliveryOrder?> batchOrders = await Future.wait(
          batch.map((ExternalDelivery summary) async {
            try {
              final ExternalDeliveryDetail detail = await _orderRepository
                  .fetchDetail(summary.name);
              return _deliveryOrderFromDetail(detail);
            } catch (_) {
              return null;
            }
          }),
        );
        orders.addAll(batchOrders.whereType<DeliveryOrder>());
      }

      orders.sort((DeliveryOrder a, DeliveryOrder b) {
        final int compareDistance = a.distanceKm.compareTo(b.distanceKm);
        if (compareDistance != 0) {
          return compareDistance;
        }
        return a.orderId.compareTo(b.orderId);
      });

      _availableOrders
        ..clear()
        ..addAll(orders);
      _orderLoadingError = null;
    } catch (e) {
      _orderLoadingError = 'Failed to fetch orders: $e';
    } finally {
      _isLoadingOrders = false;
      notifyListeners();
    }
  }

  Future<void> fetchActiveOrder({bool silent = false}) async {
    if (!silent) {
      _isFetchingActiveOrder = true;
      notifyListeners();
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // Read multi-order list; fall back to legacy single-order key for migration.
      List<String> orderIds = [];
      final String? idsJson = prefs.getString(_prefActiveOrderIds);
      if (idsJson != null && idsJson.isNotEmpty) {
        final decoded = jsonDecode(idsJson);
        if (decoded is List) {
          orderIds = decoded.map((e) => e.toString()).toList();
        }
      } else {
        // Migration: check old single-order key.
        final String? legacyId = _nullIfBlank(
          prefs.getString(_prefActiveOrderId),
        );
        if (legacyId != null) orderIds = [legacyId];
      }

      // Restore trip IDs map.
      final Map<String, String> restoredTripIds = {};
      final String? tripIdsJson = prefs.getString(_prefActiveTripIdsMap);
      if (tripIdsJson != null && tripIdsJson.isNotEmpty) {
        final decoded = jsonDecode(tripIdsJson);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            restoredTripIds[k.toString()] = v.toString();
          });
        }
      } else {
        // Migration: check legacy trip ID key.
        final String? legacyTripId = _nullIfBlank(
          prefs.getString(_prefActiveTripId),
        );
        if (legacyTripId != null && orderIds.isNotEmpty) {
          restoredTripIds[orderIds.first] = legacyTripId;
        }
      }

      if (orderIds.isEmpty) {
        _activeOrders.clear();
        _activeTripIds.clear();
        _acceptedOrders.clear();
        await _persistActiveOrders();
        PartnerWidgetManager.updateWidget(
          isOnline: _isOnline,
          todayEarnings: _earnings.today,
          activeOrder: null,
        );
        notifyListeners();
        return;
      }

      // For silent restores, show cached orders instantly while the network
      // refresh runs. This makes orders appear in < 50ms instead of waiting
      // for 1+ network round-trips.
      if (silent && _activeOrders.isEmpty) {
        final String? cachedJson = prefs.getString(_prefActiveOrdersCache);
        if (cachedJson != null && cachedJson.isNotEmpty) {
          try {
            final dynamic decoded = jsonDecode(cachedJson);
            if (decoded is List && decoded.isNotEmpty) {
              final List<DeliveryOrder> cachedOrders = decoded
                  .whereType<Map<String, dynamic>>()
                  .map(_deliveryOrderFromCache)
                  .toList();
              if (cachedOrders.isNotEmpty) {
                _activeOrders.addAll(cachedOrders);
                for (final entry in restoredTripIds.entries) {
                  _activeTripIds[entry.key] = entry.value;
                }
                notifyListeners();
              }
            }
          } catch (_) {}
        }
      }

      _activeOrders.clear();
      _activeTripIds.clear();
      const terminalStatuses = {
        OrderStatus.delivered,
        OrderStatus.cancelled,
        OrderStatus.rejected,
      };

      // Fetch all order details in parallel instead of sequentially.
      final fetchResults = await Future.wait(
        orderIds.map((orderId) async {
          try {
            final detail = await _orderRepository.fetchDetail(orderId);
            return (orderId: orderId, detail: detail);
          } catch (_) {
            return null;
          }
        }),
      );

      for (final result in fetchResults) {
        if (result == null) continue;
        final orderId = result.orderId;
        final detail = result.detail;
        final OrderStatus status = _mapExternalStatus(detail.status);
        if (terminalStatuses.contains(status)) continue;
        final DeliveryOrder order = _deliveryOrderFromDetail(detail).copyWith(
          orderStatus: status,
          assignmentStatus: OrderAssignmentStatus.assigned,
          assignedDeliveryPartnerId: _profile?.mobile ?? 'PARTNER001',
          reachedStoreAt: status == OrderStatus.reachedPickup
              ? DateTime.now()
              : null,
          deliveryPartnerLocation: _partnerLiveLocation,
        );
        _activeOrders.add(order);
        if (restoredTripIds.containsKey(orderId)) {
          _activeTripIds[orderId] = restoredTripIds[orderId]!;
        }
        _replaceAcceptedOrder(order);
      }

      _currentlyViewedOrderIndex = _currentlyViewedOrderIndex.clamp(
        0,
        _activeOrders.isEmpty ? 0 : _activeOrders.length - 1,
      );
      await _persistActiveOrders();

      if (_activeOrders.isNotEmpty) unawaited(_startLocationPingIfReady());
      PartnerWidgetManager.updateWidget(
        isOnline: _isOnline,
        todayEarnings: _earnings.today,
        activeOrder: activeOrder,
      );
      notifyListeners();
    } catch (_) {
      notifyListeners();
    } finally {
      _isFetchingActiveOrder = false;
      notifyListeners();
    }
  }

  Future<String?> acceptOrder(String orderId) async {
    // Offline drivers must not be able to take on work. This is the primary
    // guard for the order-details and orders-by-location accept flows.
    if (!_isOnline) {
      return 'You are Offline. Go Online to accept orders.';
    }
    if (_activeOrders.any((o) => o.orderId == orderId)) {
      return 'Order already accepted';
    }
    if (_activeOrders.length >= maxConcurrentOrders) {
      return 'You can only have $maxConcurrentOrders active orders at a time';
    }

    final int index = _availableOrders.indexWhere(
      (order) => order.orderId == orderId,
    );
    DeliveryOrder? cachedOrder = index >= 0 ? _availableOrders[index] : null;

    if (cachedOrder == null) {
      try {
        final ExternalDeliveryDetail detail = await _orderRepository
            .fetchDetail(orderId);
        cachedOrder = _deliveryOrderFromDetail(detail);
      } catch (_) {
        return 'Order not found';
      }
    }

    if (cachedOrder.assignmentStatus == OrderAssignmentStatus.assigned) {
      return 'Order already assigned to another partner';
    }

    // Fresh server check — guards against race condition where another partner
    // accepted the same order between the list load and this tap.
    try {
      final ExternalDeliveryDetail freshDetail = await _orderRepository
          .fetchDetail(orderId);
      if (freshDetail.status.toLowerCase() != 'pending') {
        return 'This order was just taken by another partner';
      }
    } catch (_) {
      // Non-fatal — proceed with acceptance if the check itself fails.
    }

    try {
      await _orderRepository.updateStatusViaSetValue(orderId, 'Added to Trip');

      // Create and submit an External Delivery Trip in Frappe so the web
      // dashboard reflects the accepted order immediately.
      try {
        final String tripName = await _orderRepository.createTripByOrderName(
          orderId,
        );
        _activeTripIds[orderId] = tripName;
      } catch (_) {
      }

      // Stamp driver on the order record so it is queryable by driver after
      // logout/login (SharedPreferences are cleared on logout).
      try {
        if (_driverName != null && _driverName!.isNotEmpty) {
          await _orderRepository.setDriverOnOrder(orderId, _driverName!);
        }
      } catch (_) {
      }

      _availableOrders.removeWhere((order) => order.orderId == orderId);
      final ExternalDeliveryDetail detail = await _orderRepository.fetchDetail(
        orderId,
      );
      final OrderStatus fetchedStatus = _mapExternalStatus(detail.status);
      final DeliveryOrder newOrder = _deliveryOrderFromDetail(detail).copyWith(
        orderStatus: fetchedStatus == OrderStatus.pending
            ? OrderStatus.accepted
            : fetchedStatus,
        assignmentStatus: OrderAssignmentStatus.assigned,
        assignedDeliveryPartnerId: _profile?.mobile ?? 'PARTNER001',
      );
      _activeOrders.add(newOrder);
      _currentlyViewedOrderIndex = _activeOrders.length - 1;
      _replaceAcceptedOrder(newOrder);
      unawaited(_persistActiveOrders());
      // Start pinging if this is the first active order.
      if (_activeOrders.length == 1) unawaited(_startLocationPingIfReady());
      _performance = _performance.copyWith(
        acceptanceRate: min(100, _performance.acceptanceRate + 0.8),
      );
      _notices.insert(
        0,
        AppNotice(
          title: 'Order Accepted',
          message: 'Order $orderId has been accepted by you.',
          time: DateTime.now(),
        ),
      );
      PartnerWidgetManager.updateWidget(
        isOnline: _isOnline,
        todayEarnings: _earnings.today,
        activeOrder: activeOrder,
      );
      notifyListeners();
      // Key by orderId so it matches tripCompleted's tripRef in this flow.
      _tripAcceptedTimes[orderId] = DateTime.now();
      _writeTimingEvent(
        eventType: TimingEventType.tripAccepted,
        tripRef: _activeTripIds[orderId],
      );
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  Future<String?> rejectOrder(String orderId) async {
    // "Rejected" is not a valid Frappe status — leave the order as Pending
    // so another delivery partner can still pick it up.
    _availableOrders.removeWhere((order) => order.orderId == orderId);
    _acceptedOrders.removeWhere((order) => order.orderId == orderId);
    if (_activeOrders.any((o) => o.orderId == orderId)) {
      clearOrder(orderId);
    }

    _performance = _performance.copyWith(
      acceptanceRate: max(0, _performance.acceptanceRate - 1.2),
    );

    _notices.insert(
      0,
      AppNotice(
        title: 'Order Rejected',
        message: 'Order $orderId has been rejected.',
        time: DateTime.now(),
      ),
    );

    PartnerWidgetManager.updateWidget(
      isOnline: _isOnline,
      todayEarnings: _earnings.today,
      activeOrder: activeOrder,
    );
    notifyListeners();
    return null;
  }

  Future<String?> reachedPickup(String orderId) async {
    final order = _activeOrders.where((o) => o.orderId == orderId).firstOrNull;
    if (order == null) return 'No active order found';
    if (order.orderStatus != OrderStatus.accepted) {
      return 'Order must be accepted first';
    }
    return updateOrderStatus(OrderStatus.reachedPickup, orderId: orderId);
  }

  void _replaceAcceptedOrder(DeliveryOrder order) {
    final int acceptedIndex = _acceptedOrders.indexWhere(
      (item) => item.orderId == order.orderId,
    );
    if (acceptedIndex == -1) {
      _acceptedOrders.add(order);
      return;
    }
    _acceptedOrders[acceptedIndex] = order;
  }

  Future<void> _persistActiveOrderId(String? orderId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String normalized = _nullIfBlank(orderId) ?? '';
    if (normalized.isEmpty) {
      await prefs.remove(_prefActiveOrderId);
    } else {
      await prefs.setString(_prefActiveOrderId, normalized);
    }
  }

  Future<void> _restoreActiveOrder(String orderId) async {
    // Silent — orders appear in background without showing a spinner on open.
    await fetchActiveOrder(silent: true);
  }

  /// Fallback restore used after logout/login when SharedPreferences no longer
  /// hold active order IDs. Queries the server for all in-progress orders
  /// assigned to the logged-in driver and restores all of them.
  Future<void> _tryRestoreActiveOrderByDriver() async {
    if (_driverName == null || _driverName!.isEmpty) return;
    try {
      // Fetch all active orders for this driver in one shot.
      final summaries =
          await _orderRepository.fetchActiveOrdersForDriverDirect();
      if (summaries.isEmpty) return;

      // Build orderId → tripId map across all active trips (best-effort).
      Map<String, String> tripIdByOrder = {};
      try {
        tripIdByOrder = await _orderRepository.fetchActiveTripOrderMap(
          _driverName!,
        );
      } catch (_) {}

      const terminalStatuses = {
        OrderStatus.delivered,
        OrderStatus.cancelled,
        OrderStatus.rejected,
        OrderStatus.pending,
      };

      // Fetch all order details in parallel.
      final ids = summaries
          .map((s) => s.name.trim())
          .where((id) => id.isNotEmpty && !_activeOrders.any((o) => o.orderId == id))
          .toList();

      final fetchResults = await Future.wait(
        ids.map((id) async {
          try {
            final detail = await _orderRepository.fetchDetail(id);
            return (id: id, detail: detail);
          } catch (_) {
            return null;
          }
        }),
      );

      for (final result in fetchResults) {
        if (result == null) continue;
        final OrderStatus status = _mapExternalStatus(result.detail.status);
        if (terminalStatuses.contains(status)) continue;

        final restoredOrder = _deliveryOrderFromDetail(result.detail).copyWith(
          orderStatus: status,
          assignmentStatus: OrderAssignmentStatus.assigned,
          assignedDeliveryPartnerId: _profile?.mobile ?? 'PARTNER001',
          deliveryPartnerLocation: _partnerLiveLocation,
        );
        _activeOrders.add(restoredOrder);
        final tripId = tripIdByOrder[result.id];
        if (tripId != null) _activeTripIds[result.id] = tripId;
        _replaceAcceptedOrder(restoredOrder);
      }

      if (_activeOrders.isEmpty) return;
      _currentlyViewedOrderIndex = 0;
      await _persistActiveOrders();
      unawaited(_startLocationPingIfReady());
      PartnerWidgetManager.updateWidget(
        isOnline: _isOnline,
        todayEarnings: _earnings.today,
        activeOrder: activeOrder,
      );
      notifyListeners();
    } catch (_) {}
  }

  String? _toFrappeStatus(OrderStatus status) {
    switch (status) {
      case OrderStatus.reachedPickup:
        return 'Reached Pickup';
      case OrderStatus.pickedUp:
        return 'Picked Up';
      case OrderStatus.outForDelivery:
        return 'Out for Delivery';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.failed:
        return 'Failed';
      default:
        return null;
    }
  }

  String? _toTripStopStatus(OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.failed:
      case OrderStatus.cancelled:
        return 'Failed';
      default:
        return null;
    }
  }

  OrderStatus _mapExternalStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'accepted':
      case 'added to trip':
        return OrderStatus.accepted;
      case 'rejected':
        return OrderStatus.rejected;
      case 'reached pickup':
      case 'reachedpickup':
        return OrderStatus.reachedPickup;
      case 'picked up':
      case 'pickedup':
        return OrderStatus.pickedUp;
      case 'out for delivery':
      case 'outfordelivery':
        return OrderStatus.outForDelivery;
      case 'delivered':
        return OrderStatus.delivered;
      case 'failed':
        return OrderStatus.failed;
      case 'cancelled':
      case 'canceled':
        return OrderStatus.cancelled;
      case 'returned':
      case 'return initiated':
        return OrderStatus.returned;
      case 'pending':
      default:
        return OrderStatus.pending;
    }
  }

  DeliveryOrder _deliveryOrderFromDetail(ExternalDeliveryDetail detail) {
    final List<OrderItem> items = detail.items
        .map(
          (DeliveryItem item) => OrderItem(
            name: item.itemName.isNotEmpty ? item.itemName : 'Item',
            quantity: item.qty.isFinite && item.qty > 0 ? item.qty.round() : 1,
            price: item.amount ?? item.rate ?? 0,
          ),
        )
        .toList();

    final double totalAmount = items.fold<double>(
      0,
      (double sum, OrderItem item) => sum + (item.price * item.quantity),
    );

    // The order's real drop coordinates, or null when the backend didn't
    // provide them. `0` is the app-wide sentinel for "no coordinates"
    // (see hasCoords checks in the listing/details screens), so we fall back
    // to 0 rather than inventing a location — a bogus coordinate would wrongly
    // enable "Open in Maps" and route the driver to the wrong place.
    final double? orderLatitude = detail.latitude;
    final double? orderLongitude = detail.longitude;
    final double latitude = orderLatitude ?? 0;
    final double longitude = orderLongitude ?? 0;
    final OrderStatus status = _mapExternalStatus(detail.status);

    // Frappe stores addresses with HTML markup (<br> for line breaks,
    // sometimes <a>, <span>, etc.). Sanitize once here so every consumer
    // of DeliveryOrder gets plain text with real newlines.
    final String dropAddress = Formatters.stripHtml(
      detail.deliveryAddress,
      preserveLineBreaks: true,
    );
    final String pickupAddress = Formatters.stripHtml(
      detail.pickupAddress,
      preserveLineBreaks: true,
    );
    final String storeAddress = pickupAddress.isNotEmpty
        ? pickupAddress
        : detail.storeUrl;

    return DeliveryOrder(
      id: detail.name,
      orderId: detail.name,
      customerName: detail.customerName,
      customerPhone: detail.contactMobile ?? '',
      deliveryAddress: dropAddress,
      storeId: detail.storeUrl.isNotEmpty ? detail.storeUrl : detail.storeName,
      storeName: detail.storeName,
      storeContact: detail.contactMobile ?? '',
      storeAddress: storeAddress,
      orderItems: items,
      orderStatus: status,
      latitude: latitude,
      longitude: longitude,
      contactNumber: detail.contactMobile ?? '',
      customerEmail: detail.customerEmail ?? '',
      pickup: pickupAddress.isNotEmpty ? pickupAddress : detail.storeUrl,
      drop: dropAddress,
      deliveryInstructions: '',
      paymentMode: detail.paymentMode ?? '',
      // Prefer the server-computed distance (from the radius-aware
      // `list_available_deliveries` feed) when present; otherwise fall back to
      // a client-side Haversine estimate from the driver's current location.
      distanceKm: (detail.distanceKm != null && detail.distanceKm! > 0)
          ? detail.distanceKm!
          : (_currentLatitude != null &&
                    _currentLongitude != null &&
                    orderLatitude != null &&
                    orderLongitude != null)
              ? _calculateDistance(
                  _currentLatitude!,
                  _currentLongitude!,
                  orderLatitude,
                  orderLongitude,
                )
              : 0,
      estimatedEarnings: detail.grandTotal ?? totalAmount,
      assignmentStatus: status == OrderStatus.pending
          ? OrderAssignmentStatus.unassigned
          : OrderAssignmentStatus.assigned,
      assignedDeliveryPartnerId: _profile?.mobile ?? 'PARTNER001',
      reachedStoreAt: status == OrderStatus.reachedPickup
          ? DateTime.now()
          : null,
      deliveryPartnerLocation: _partnerLiveLocation,
    );
  }

  DeliveryOrder buildDeliveryOrderFromDetail(ExternalDeliveryDetail detail) {
    return _deliveryOrderFromDetail(detail);
  }

  OrderStatus mapStatus(String status) => _mapExternalStatus(status);

  bool validateProximityToStore(
    double storeLat,
    double storeLng,
    double partnerLat,
    double partnerLng,
  ) {
    const double maxDistanceKm = 0.5;
    final double distance = _calculateDistance(
      storeLat,
      storeLng,
      partnerLat,
      partnerLng,
    );
    return distance <= maxDistanceKm;
  }

  double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadius = 6371;
    final double dLat = _toRadians(lat2 - lat1);
    final double dLng = _toRadians(lng2 - lng1);
    final double a =
        _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_toRadians(lat1)) *
            _cos(_toRadians(lat2)) *
            _sin(dLng / 2) *
            _sin(dLng / 2);
    final double c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * 3.141592653589793 / 180;
  double _sin(double x) => _taylorSin(x);
  double _cos(double x) => _taylorCos(x);
  double _sqrt(double x) => _newtonSqrt(x);
  double _atan2(double y, double x) => _approximateAtan2(y, x);

  double _taylorSin(double x) {
    x = x % (2 * 3.141592653589793);
    double result = x;
    double term = x;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }

  double _taylorCos(double x) {
    x = x % (2 * 3.141592653589793);
    double result = 1;
    double term = 1;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }

  double _newtonSqrt(double x) {
    if (x < 0) return double.nan;
    if (x == 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  double _approximateAtan2(double y, double x) {
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.141592653589793;
    if (x < 0 && y < 0) return _atan(y / x) - 3.141592653589793;
    if (x == 0 && y > 0) return 3.141592653589793 / 2;
    if (x == 0 && y < 0) return -3.141592653589793 / 2;
    return 0;
  }

  double _atan(double x) {
    if (x.abs() > 1) {
      return (x > 0 ? 1 : -1) * (3.141592653589793 / 2 - _atan(1 / x));
    }
    double result = x;
    double term = x;
    for (int i = 1; i <= 20; i++) {
      term *= -x * x;
      result += term / (2 * i + 1);
    }
    return result;
  }

  void startLiveLocationTracking() {
    _liveLocationTimer?.cancel();
    _liveLocationTimer = Timer.periodic(
      Duration(seconds: _trackingInterval),
      (_) => _updateLiveLocation(),
    );
    unawaited(_startLocationPingIfReady());
  }

  void stopLiveLocationTracking() {
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;
    _locationPingSubscription?.cancel();
    _locationPingSubscription = null;
    LocationPingService.stop();
  }

  void _updateLiveLocation() {
    if (_currentLatitude == null || _currentLongitude == null) return;
    _partnerLiveLocation = GeoLocation(
      latitude: _currentLatitude!,
      longitude: _currentLongitude!,
    );
    for (int i = 0; i < _activeOrders.length; i++) {
      _activeOrders[i] = _activeOrders[i].copyWith(
        deliveryPartnerLocation: _partnerLiveLocation,
      );
    }
    notifyListeners();
  }

  Future<void> _startLocationPingIfReady() async {
    if (_activeOrders.isEmpty) return;
    // Use the first active order's trip for pinging (driver location tracking).
    final DeliveryOrder firstOrder = _activeOrders.first;
    final String? tripId = _activeTripIds[firstOrder.orderId];
    if (tripId == null) {
      return;
    }
    final String? authHeader = await _buildAuthHeader();
    if (authHeader == null) return;
    await LocationPingService.start(
      tripId: tripId,
      deliveryId: firstOrder.orderId,
      authHeader: authHeader,
      baseUrl: ApiConstants.erpBaseUrl,
    );
    _locationPingSubscription?.cancel();
    _locationPingSubscription = LocationPingService.locationUpdates.listen((
      data,
    ) {
      if (data == null) return;
      _currentLatitude = (data['lat'] as num?)?.toDouble();
      _currentLongitude = (data['lng'] as num?)?.toDouble();
      _updateLiveLocation();
    });
  }

  Future<String?> _buildAuthHeader() async {
    // Prefer API key:secret — doesn't expire and works reliably in background.
    final String? apiKey = await SecureTokenStorage.read(
      SecureTokenStorage.apiKey,
    );
    final String? apiSecret = await SecureTokenStorage.read(
      SecureTokenStorage.apiSecret,
    );
    if (apiKey != null &&
        apiKey.isNotEmpty &&
        apiSecret != null &&
        apiSecret.isNotEmpty) {
      return 'token $apiKey:$apiSecret';
    }
    // Fall back to session/bearer token.
    final String? token =
        _sessionToken ??
        await SecureTokenStorage.read(SecureTokenStorage.accessToken);
    if (token == null || token.isEmpty) return null;
    final String tokenType =
        (await SecureTokenStorage.read(SecureTokenStorage.tokenType) ?? '')
            .trim();
    return tokenType.toLowerCase() == 'token'
        ? 'token $token'
        : 'Bearer $token';
  }

  Future<void> _persistActiveTripId(String? tripId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (tripId == null || tripId.isEmpty) {
      await prefs.remove(_prefActiveTripId);
    } else {
      await prefs.setString(_prefActiveTripId, tripId);
    }
  }

  Future<void> _persistActiveOrders() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> ids = _activeOrders.map((o) => o.orderId).toList();
    if (ids.isEmpty) {
      await prefs.remove(_prefActiveOrderIds);
      await prefs.remove(_prefActiveTripIdsMap);
      await prefs.remove(_prefActiveOrdersCache);
      // Also clear legacy keys.
      await prefs.remove(_prefActiveOrderId);
      await prefs.remove(_prefActiveTripId);
    } else {
      await prefs.setString(_prefActiveOrderIds, jsonEncode(ids));
      await prefs.setString(
        _prefActiveTripIdsMap,
        jsonEncode(_activeTripIds),
      );
      // Save full order data so the next launch can show orders instantly
      // from cache while the network refresh runs in the background.
      final List<Map<String, dynamic>> cacheList = _activeOrders
          .map(
            (o) => <String, dynamic>{
              'orderId': o.orderId,
              'customerName': o.customerName,
              'customerPhone': o.customerPhone,
              'customerEmail': o.customerEmail,
              'deliveryAddress': o.deliveryAddress,
              'storeId': o.storeId,
              'storeName': o.storeName,
              'storeContact': o.storeContact,
              'storeAddress': o.storeAddress,
              'orderStatus': o.orderStatus.name,
              'latitude': o.latitude,
              'longitude': o.longitude,
              'contactNumber': o.contactNumber,
              'pickup': o.pickup,
              'drop': o.drop,
              'distanceKm': o.distanceKm,
              'estimatedEarnings': o.estimatedEarnings,
              'paymentMode': o.paymentMode,
              'deliveryInstructions': o.deliveryInstructions,
              'acceptedAt': o.acceptedAt?.toIso8601String(),
              'orderItems': o.orderItems
                  .map(
                    (i) => <String, dynamic>{
                      'name': i.name,
                      'quantity': i.quantity,
                      'price': i.price,
                    },
                  )
                  .toList(),
            },
          )
          .toList();
      await prefs.setString(_prefActiveOrdersCache, jsonEncode(cacheList));
      // Write first order to legacy key for backward compat.
      await prefs.setString(_prefActiveOrderId, ids.first);
      final String? firstTripId = _activeTripIds[ids.first];
      if (firstTripId != null) {
        await prefs.setString(_prefActiveTripId, firstTripId);
      }
    }
  }

  DeliveryOrder _deliveryOrderFromCache(Map<String, dynamic> json) {
    final String statusName = (json['orderStatus'] as String?) ?? 'accepted';
    final OrderStatus status = OrderStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => OrderStatus.accepted,
    );
    final dynamic itemsRaw = json['orderItems'];
    final List<OrderItem> items = itemsRaw is List
        ? itemsRaw
            .whereType<Map<String, dynamic>>()
            .map(
              (i) => OrderItem(
                name: (i['name'] as String?) ?? '',
                quantity: (i['quantity'] as int?) ?? 1,
                price: (i['price'] as num?)?.toDouble() ?? 0,
              ),
            )
            .toList()
        : <OrderItem>[];
    return DeliveryOrder(
      orderId: (json['orderId'] as String?) ?? '',
      customerName: (json['customerName'] as String?) ?? '',
      customerPhone: (json['customerPhone'] as String?) ?? '',
      deliveryAddress: (json['deliveryAddress'] as String?) ?? '',
      storeId: (json['storeId'] as String?) ?? '',
      storeName: (json['storeName'] as String?) ?? '',
      storeContact: (json['storeContact'] as String?) ?? '',
      storeAddress: (json['storeAddress'] as String?) ?? '',
      orderItems: items,
      orderStatus: status,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      contactNumber: (json['contactNumber'] as String?) ?? '',
      customerEmail: (json['customerEmail'] as String?) ?? '',
      pickup: (json['pickup'] as String?) ?? '',
      drop: (json['drop'] as String?) ?? '',
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
      estimatedEarnings: (json['estimatedEarnings'] as num?)?.toDouble() ?? 0,
      paymentMode: (json['paymentMode'] as String?) ?? '',
      deliveryInstructions: (json['deliveryInstructions'] as String?) ?? '',
      acceptedAt: json['acceptedAt'] != null
          ? DateTime.tryParse(json['acceptedAt'] as String)
          : null,
      assignmentStatus: OrderAssignmentStatus.assigned,
      assignedDeliveryPartnerId: _profile?.mobile ?? 'PARTNER001',
    );
  }

  String t(
    String key, [
    Map<String, String> params = const <String, String>{},
  ]) {
    return AppStrings.format(
      _languageCode.isEmpty ? 'en' : _languageCode,
      key,
      params,
    );
  }

  String orderStatusLabel(OrderProgressStatus status) {
    return LocalizedText.orderStatus(
      _languageCode.isEmpty ? 'en' : _languageCode,
      status,
    );
  }

  String verificationStatusLabel(VerificationStatus status) {
    return LocalizedText.verificationStatus(
      _languageCode.isEmpty ? 'en' : _languageCode,
      status,
    );
  }

  String aiMessage(dynamic value) {
    return LocalizedText.resolveAiMessage(
      _languageCode.isEmpty ? 'en' : _languageCode,
      value,
    );
  }

  Future<void> _persistSession(Map<String, dynamic> message) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? refreshToken = _nullIfBlank(
      message['refresh_token']?.toString(),
    );
    final String? tokenType = _nullIfBlank(message['token_type']?.toString());
    final String? fullName = _nullIfBlank(message['full_name']?.toString());
    final String? mobile = _nullIfBlank(message['mobile_no']?.toString());
    final String? email = _nullIfBlank(message['email']?.toString());
    final String? driverName = _nullIfBlank(message['driver_name']?.toString());
    final String? clientId = _nullIfBlank(message['client_id']?.toString());
    final String? apiKey = _nullIfBlank(message['api_key']?.toString());
    final String? apiSecretVal = _nullIfBlank(
      message['api_secret']?.toString(),
    );
    final int? expiresIn = int.tryParse(
      message['expires_in']?.toString() ?? '',
    );

    final bool backendProfileCompleted =
        message['profile_completed']?.toString() == '1';
    final bool backendKycCompleted =
        message['kyc_completed']?.toString() == '1';

    if (driverName != null) {
      _driverName = driverName;
    }
    if (clientId != null) {
      _clientId = clientId;
    }
    if (apiKey != null) {
      _apiKey = apiKey;
    }
    if (apiSecretVal != null) {
      _apiSecret = apiSecretVal;
    }
    if (backendProfileCompleted) {
      _profileCompleted = true;
    }
    _kycCompleted = backendKycCompleted;
    _tokenType = tokenType ?? _tokenType;

    // These secure-storage writes target independent keys, so run them
    // concurrently instead of one-by-one — each is a platform-channel round
    // trip and was adding up to several seconds of serial latency here.
    await Future.wait(<Future<dynamic>>[
      SecureTokenStorage.write(SecureTokenStorage.accessToken, _sessionToken!),
      if (refreshToken != null)
        SecureTokenStorage.write(SecureTokenStorage.refreshToken, refreshToken),
      if (tokenType != null)
        SecureTokenStorage.write(SecureTokenStorage.tokenType, tokenType),
      if (expiresIn != null)
        SecureTokenStorage.write(
          SecureTokenStorage.expiresIn,
          expiresIn.toString(),
        ),
      _persistAccessTokenExpiry(expiresIn),
      if (clientId != null)
        SecureTokenStorage.write(SecureTokenStorage.clientId, clientId),
      if (apiKey != null)
        SecureTokenStorage.write(SecureTokenStorage.apiKey, apiKey),
      if (apiSecretVal != null)
        SecureTokenStorage.write(SecureTokenStorage.apiSecret, apiSecretVal),
    ]);

    await Future.wait(<Future<bool>>[
      prefs.setBool(_prefRememberMe, _rememberMe),
      prefs.remove(_prefCurrentLat),
      prefs.remove(_prefCurrentLng),
      prefs.remove(_prefCurrentLocationLabel),
      if (fullName != null) prefs.setString(_prefFullName, fullName),
      if (mobile != null) prefs.setString(_prefMobile, mobile),
      if (email != null) prefs.setString(_prefEmail, email),
      if (driverName != null) prefs.setString(_prefDriverName, driverName),
      prefs.setBool(_prefProfileCompleted, _profileCompleted),
      prefs.setBool(_prefKycCompleted, _kycCompleted),
    ]);
  }

  Map<String, dynamic> _decodeJsonMap(String raw) {
    if (raw.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return <String, dynamic>{};
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _extractMethodData(Map<String, dynamic> payload) {
    final dynamic messageNode = payload['message'];
    if (messageNode is Map<String, dynamic>) {
      return messageNode;
    }
    return payload;
  }

  String? _extractServerError(Map<String, dynamic> payload) {
    final String payloadStatus = (payload['status']?.toString() ?? '')
        .toLowerCase();

    final String? explicitError = _nullIfBlank(
      payload['_error_message']?.toString(),
    );
    if (explicitError != null) {
      return explicitError;
    }

    final String? fromServerMessages = _extractFromServerMessages(
      payload['_server_messages'],
    );
    if (fromServerMessages != null) {
      return fromServerMessages;
    }

    final dynamic messageNode = payload['message'];
    if (messageNode is String && messageNode.trim().isNotEmpty) {
      if (payloadStatus != 'success') {
        return messageNode;
      }
      return null;
    }
    if (messageNode is Map<String, dynamic>) {
      final String status = (messageNode['status']?.toString() ?? '')
          .toLowerCase();
      final String? fromMessage = _nullIfBlank(
        messageNode['message']?.toString(),
      );
      if (fromMessage != null && status != 'success') {
        return fromMessage;
      }
    }

    final String? exception = _nullIfBlank(payload['exception']?.toString());
    if (exception != null) {
      return exception;
    }

    final String? exc = _nullIfBlank(payload['exc']?.toString());
    if (exc != null) {
      return exc;
    }

    final String? excType = _nullIfBlank(payload['exc_type']?.toString());
    if (excType != null) {
      return excType;
    }
    return null;
  }

  String? _extractFromServerMessages(dynamic raw) {
    if (raw == null) {
      return null;
    }

    if (raw is String && raw.trim().isEmpty) {
      return null;
    }

    try {
      final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! List) {
        return _nullIfBlank(decoded?.toString());
      }

      for (final dynamic entry in decoded) {
        final String? message = _extractSingleServerMessage(entry);
        if (message != null) {
          return message;
        }
      }
    } catch (_) {
      return _nullIfBlank(raw.toString());
    }

    return null;
  }

  String? _extractSingleServerMessage(dynamic entry) {
    if (entry == null) {
      return null;
    }

    if (entry is Map<String, dynamic>) {
      return _nullIfBlank(entry['message']?.toString()) ??
          _nullIfBlank(entry['title']?.toString());
    }

    if (entry is String) {
      final String text = entry.trim();
      if (text.isEmpty) {
        return null;
      }

      try {
        final dynamic inner = jsonDecode(text);
        if (inner is Map<String, dynamic>) {
          return _nullIfBlank(inner['message']?.toString()) ??
              _nullIfBlank(inner['title']?.toString());
        }
      } catch (_) {
        return text;
      }
      return _nullIfBlank(text);
    }

    return _nullIfBlank(entry.toString());
  }

  String? _normalizeMobileForDisplay(String? raw) {
    final String? value = _nullIfBlank(raw);
    if (value == null) {
      return null;
    }
    final String digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }
    if (digits.length == 10) {
      return digits;
    }
    return value;
  }

  String? _nullIfBlank(String? value) {
    if (value == null) {
      return null;
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Re-reads today's timing events from the local DB and restores all
  /// in-memory counters. Called after login so the dashboard reflects
  /// any trips/duty that occurred earlier in the day without a restart.
  Future<void> _restoreSessionFromDb() async {
    final dao = _timingDao;
    if (dao == null) return;
    final partner = _driverName ?? _profile?.mobile;
    if (partner == null || partner.trim().isEmpty) return;

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final rows = await dao.getEventsInRange(
      startOfDay,
      endOfDay,
      partner: partner.trim(),
    );

    // Duty hours from login/logout pairs (previous sessions only — current
    // session starts fresh once the driver goes online).
    final logins = rows.where((r) => r.eventType == TimingEventType.login).toList();
    final logouts = rows.where((r) => r.eventType == TimingEventType.logout).toList();
    if (logins.isNotEmpty && logouts.isNotEmpty) {
      final diff = DateTime.parse(logouts.last.eventTime)
          .difference(DateTime.parse(logins.first.eventTime));
      if (!diff.isNegative) _completedDutyToday = diff;
    }

    // Trip count.
    _completedTripsToday = rows
        .where((r) => r.eventType == TimingEventType.tripCompleted)
        .length;

    // Avg trip duration — prefs first (saved after every completion).
    final prefs = await SharedPreferences.getInstance();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final savedDate = prefs.getString(_prefTripTimeSavedDate(partner.trim()));
    if (savedDate == todayStr) {
      final savedMs = prefs.getInt(_prefTotalTripTimeTodayMs(partner.trim())) ?? 0;
      _totalTripTimeToday = Duration(milliseconds: savedMs);
    } else {
      final acceptedTimes = <String, DateTime>{};
      for (final r in rows) {
        if (r.eventType == TimingEventType.tripAccepted && r.tripName != null) {
          acceptedTimes[r.tripName!] = DateTime.parse(r.eventTime);
        }
      }
      var total = Duration.zero;
      for (final r in rows.where(
        (r) => r.eventType == TimingEventType.tripCompleted && r.tripName != null,
      )) {
        final start = acceptedTimes[r.tripName!];
        if (start != null) {
          final d = DateTime.parse(r.eventTime).difference(start);
          if (!d.isNegative) total += d;
        }
      }
      _totalTripTimeToday = total;
    }

    // Restore start times for any trips still in progress today.
    final completedRefs = rows
        .where((r) => r.eventType == TimingEventType.tripCompleted && r.tripName != null)
        .map((r) => r.tripName!)
        .toSet();
    for (final r in rows) {
      if (r.eventType == TimingEventType.tripAccepted && r.tripName != null) {
        _sessionTripAcceptances.add(r.tripName!);
        if (!completedRefs.contains(r.tripName!)) {
          _tripAcceptedTimes[r.tripName!] = DateTime.parse(r.eventTime);
        }
      }
    }

    // Restore online state so the duty-hours live ticker resumes automatically
    // after a logout+login on the same day, matching cold-restart behaviour.
    // _onlineSince is set to now (not the last DB login time) so the live
    // portion starts fresh — _completedDutyToday already covers prior sessions.
    final wasOnline = prefs.getBool(_prefIsOnline) ?? false;
    if (wasOnline) {
      _isOnline = true;
      _onlineSince = DateTime.now();
    }
  }

  void _persistTripTimeToday() {
    final driver = _driverName ?? _profile?.mobile ?? '';
    if (driver.isEmpty) return;
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _writePref((prefs) async {
      await prefs.setInt(_prefTotalTripTimeTodayMs(driver), _totalTripTimeToday.inMilliseconds);
      await prefs.setString(_prefTripTimeSavedDate(driver), dateStr);
      return true;
    });
  }

  void _writePref(Future<bool> Function(SharedPreferences prefs) writer) {
    unawaited(() async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await writer(prefs);
    }());
  }

  /// Sets a single field on the logged-in driver's Frappe Driver doc.
  /// Used to keep Driver.vehicle in sync so server-side hydration works after
  /// logout/re-login without relying on local SharedPreferences.
  Future<void> _setDriverField(String fieldname, Object value) async {
    if (_driverName == null || _driverName!.isEmpty) return;
    final Uri uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.client.set_value',
    );
    await authorizedPostJson(uri, <String, dynamic>{
      'doctype': 'Driver',
      'name': _driverName!,
      'fieldname': fieldname,
      'value': value,
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void _applyRatingFromDriverDoc(Map<String, dynamic>? driverDoc) {
    if (driverDoc == null) return;
    final dynamic ratingRaw = driverDoc['custom_avg_rating'];
    final double parsed = double.tryParse(ratingRaw?.toString() ?? '') ?? 0.0;
    _performance = _performance.copyWith(rating: parsed);
    notifyListeners();
  }

  Future<void> fetchLoggedInEmployeeDriverProfile({
    bool forceRefresh = false,
  }) async {
    if (_profileDetailsLoading) {
      return;
    }
    if (!forceRefresh && _loggedProfileDetails?.hasData == true) {
      _applyRatingFromDriverDoc(_loggedProfileDetails?.driver);
      return;
    }
    if (_sessionToken == null || _sessionToken!.isEmpty) {
      _profileDetailsError = 'Please login again to load profile';
      notifyListeners();
      return;
    }

    _profileDetailsLoading = true;
    _profileDetailsError = null;
    notifyListeners();

    try {
      final String? fetchedLoggedUser = await _fetchLoggedUser();
      final String? loggedUser =
          fetchedLoggedUser != null &&
              fetchedLoggedUser.trim().toLowerCase() == 'administrator'
          ? null
          : fetchedLoggedUser;
      String? driverName;
      String? employeeName;
      Map<String, dynamic>? driverDoc;
      Map<String, dynamic>? employeeDoc;

      // Login identity is best mapped through mobile returned in OTP login flow.
      driverName = await _findDriverByMobile();

      // Secondary mapping only if login user is available and not generic admin.
      if (driverName == null &&
          loggedUser != null &&
          loggedUser.toLowerCase() != 'administrator') {
        final String? linkedEmployeeName = await _findResourceName(
          doctype: 'Employee',
          filters: <List<String>>[
            <String>['Employee', 'user_id', '=', loggedUser],
          ],
          fields: <String>['name'],
        );
        if (linkedEmployeeName != null) {
          employeeName = linkedEmployeeName;
          driverName = await _findResourceName(
            doctype: 'Driver',
            filters: <List<String>>[
              <String>['Driver', 'employee', '=', linkedEmployeeName],
            ],
            fields: <String>['name'],
          );
        }
      }

      if (driverName != null) {
        driverDoc = await _fetchResourceDoc('Driver', driverName);
        employeeName ??= _nullIfBlank(driverDoc?['employee']?.toString());
        _existingLicenseNo = _nullIfBlank(
          driverDoc?['license_number']?.toString(),
        );
        _existingAadharNo = _nullIfBlank(
          driverDoc?['custom_aadhar_no']?.toString(),
        );
        _existingPanNo = _nullIfBlank(driverDoc?['custom_pan_no']?.toString());
        _existingLicenseUrl = _nullIfBlank(
          driverDoc?['custom_license_attachment']?.toString(),
        );
        _existingAadharUrl = _nullIfBlank(
          driverDoc?['custom_aadhar_attachment']?.toString(),
        );
        _existingPanUrl = _nullIfBlank(
          driverDoc?['custom_pan_attachment']?.toString(),
        );
        _existingIssuingDate = _nullIfBlank(
          driverDoc?['issuing_date']?.toString(),
        );
        _existingExpiryDate = _nullIfBlank(
          driverDoc?['expiry_date']?.toString(),
        );
      } else {
        // No Driver record maps to this user (a new signup, before KYC is
        // submitted). These fields pre-fill the KYC form, so they must be
        // blank rather than left holding a previous session's values.
        _clearKycIdentity();
      }
      if (employeeName != null) {
        employeeDoc = await _fetchResourceDoc('Employee', employeeName);
      }

      _loggedProfileDetails = LoggedPartnerProfileDetails(
        loggedUser: loggedUser,
        employee: employeeDoc,
        driver: driverDoc,
      );

      if (driverDoc != null) {
        _checkLicenseStatus(driverDoc);
        _applyRatingFromDriverDoc(driverDoc);
        final dynamic onlineRaw = driverDoc['custom_custom_is_online'];
        if (onlineRaw != null) {
          final bool backendOnline =
              onlineRaw == 1 ||
              onlineRaw == true ||
              onlineRaw.toString() == '1';
          if (_isOnline != backendOnline) {
            _isOnline = backendOnline;
            _writePref(
              (SharedPreferences prefs) =>
                  prefs.setBool(_prefIsOnline, _isOnline),
            );
          }
        }
        if (_driverName == null || _driverName!.isEmpty) {
          final String? fetchedName = _nullIfBlank(
            driverDoc['name']?.toString(),
          );
          if (fetchedName != null) {
            _driverName = fetchedName;
            _writePref(
              (SharedPreferences prefs) =>
                  prefs.setString(_prefDriverName, fetchedName),
            );
          }
        }

        // Seed vehicle lookup key from the Driver doc's link field.
        // SharedPreferences are wiped on logout so this restores the
        // primary key that hydrateVehicleFromBackend() needs after re-login.
        final String? vehicleFromDriverDoc = _nullIfBlank(
          driverDoc['vehicle']?.toString(),
        );
        if (vehicleFromDriverDoc != null) {
          _writePref(
            (SharedPreferences prefs) =>
                prefs.setString(_prefVehicleName, vehicleFromDriverDoc),
          );
        }

        // Seed bank lookup key from the Driver doc's link field.
        // Mirrors the vehicle seeding above — Driver.custom_bank_account is
        // the source of truth after logout clears SharedPreferences.
        // Uses custom_ prefix because the field was added via Customize Form.
        final String? bankFromDriverDoc = _nullIfBlank(
          driverDoc['custom_bank_account']?.toString(),
        );
        if (bankFromDriverDoc != null) {
          _writePref(
            (SharedPreferences prefs) =>
                prefs.setString(_prefBankDocName, bankFromDriverDoc),
          );
        }
      }

      if (!(_loggedProfileDetails?.hasData ?? false)) {
        _profileDetailsError = 'No driver profile linked to this login account';
      }

      await _syncServerProfileImageFromEmployee(employeeDoc);
      // Employee image takes priority. If no employee record exists,
      // fall back to User.user_image (where uploads go when employee is unlinked).
      if (employeeDoc == null && loggedUser != null) {
        await _syncProfileImageFromUser(loggedUser);
      }
    } catch (e) {
      _profileDetailsError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _profileDetailsLoading = false;
      notifyListeners();
    }
  }

  Future<void> _syncProfileImageFromUser(String userName) async {
    try {
      final Map<String, dynamic>? userDoc = await _fetchResourceDoc(
        'User',
        userName,
      );
      final String? userImage = _nullIfBlank(
        userDoc?['user_image']?.toString(),
      );
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _serverProfileImageUrl = userImage;
      if (userImage != null) {
        await prefs.setString(_prefServerProfileImageUrl, userImage);
      } else {
        await prefs.remove(_prefServerProfileImageUrl);
        if (_profileImagePath != null) {
          final File localFile = File(_profileImagePath!);
          if (localFile.existsSync()) {
            try {
              localFile.deleteSync();
            } catch (_) {}
          }
          _profileImagePath = null;
          await prefs.remove(_prefProfileImagePath);
        }
      }
    } catch (_) {}
  }

  Future<String?> _fetchLoggedUser() async {
    final Uri uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.auth.get_logged_user',
    );
    final Map<String, dynamic> payload = await _authorizedGet(uri);
    return _nullIfBlank(payload['message']?.toString());
  }

  Future<void> _syncServerProfileImageFromEmployee(
    Map<String, dynamic>? employeeDoc,
  ) async {
    if (employeeDoc == null) {
      // No employee record — we can't infer server state from Employee.
      // Leave local cache and _serverProfileImageUrl untouched.
      return;
    }

    final String? serverUrl = _nullIfBlank(employeeDoc['image']?.toString());
    _serverProfileImageUrl = serverUrl;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (serverUrl != null) {
      await prefs.setString(_prefServerProfileImageUrl, serverUrl);
    } else {
      await prefs.remove(_prefServerProfileImageUrl);
      // Employee exists but its image field is empty → deleted from web.
      // Clear the stale local file to reflect that.
      if (_profileImagePath != null) {
        final File localFile = File(_profileImagePath!);
        if (localFile.existsSync()) {
          try {
            localFile.deleteSync();
          } catch (_) {}
        }
        _profileImagePath = null;
        await prefs.remove(_prefProfileImagePath);
      }
    }
  }

  Future<String?> _findDriverByMobile() async {
    final String? mobile = _normalizedMobileForSearch(_profile?.mobile);
    if (mobile == null) {
      return null;
    }

    final List<String> candidates = <String>[mobile, '91$mobile', '+91$mobile'];

    for (final String candidate in candidates) {
      final String? found = await _findResourceName(
        doctype: 'Driver',
        filters: <List<String>>[
          <String>['Driver', 'cell_number', '=', candidate],
        ],
        fields: <String>['name'],
      );
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  Future<String?> _findResourceName({
    required String doctype,
    required List<List<String>> filters,
    List<String> fields = const <String>['name'],
  }) async {
    final Map<String, String> queryParameters = <String, String>{
      'fields': jsonEncode(fields),
      'limit_page_length': '1',
    };
    if (filters.isNotEmpty) {
      queryParameters['filters'] = jsonEncode(filters);
    }
    final Uri uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/resource/${Uri.encodeComponent(doctype)}',
    ).replace(queryParameters: queryParameters);

    final Map<String, dynamic> payload = await _authorizedGet(uri);
    final dynamic rows = payload['data'];
    if (rows is List && rows.isNotEmpty) {
      final dynamic first = rows.first;
      if (first is Map<String, dynamic>) {
        return _nullIfBlank(first['name']?.toString());
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _fetchResourceDoc(
    String doctype,
    String name,
  ) async {
    final Uri uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/resource/${Uri.encodeComponent(doctype)}/${Uri.encodeComponent(name)}',
    );
    final Map<String, dynamic> payload = await _authorizedGet(uri);
    final dynamic data = payload['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return null;
  }

  Future<Map<String, dynamic>> _authorizedGet(Uri uri) async {
    final List<Map<String, String>> authHeaders = _authorizationHeaders();
    String? lastError;
    for (final Map<String, String> headers in authHeaders) {
      final http.Response response = await http
          .get(uri, headers: headers)
          .timeout(_networkTimeout);
      final Map<String, dynamic> payload = _decodeJsonMap(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return payload;
      }

      final String message =
          _extractServerError(payload) ??
          'Profile request failed (${response.statusCode})';
      lastError = message;

      // Try the next auth strategy only for authorization failures.
      if (response.statusCode != 401 && response.statusCode != 403) {
        throw Exception(message);
      }
    }

    // All header candidates failed with 401/403 — try refreshing the token.
    if (await refreshSession()) {
      final Map<String, String> refreshedHeaders =
          _authorizationHeaders().first;
      final http.Response retryResp = await http
          .get(uri, headers: refreshedHeaders)
          .timeout(_networkTimeout);
      final Map<String, dynamic> retryPayload = _decodeJsonMap(retryResp.body);
      if (retryResp.statusCode >= 200 && retryResp.statusCode < 300) {
        return retryPayload;
      }
    }
    throw Exception(lastError ?? 'Authentication failed for GET $uri');
  }

  Future<Map<String, dynamic>> authorizedPutJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final List<Map<String, String>> authHeaders = _authorizationHeaders(
      contentType: 'application/json',
    );

    String? lastError;
    final String encodedBody = jsonEncode(body);
    for (final Map<String, String> headers in authHeaders) {
      final http.Response response = await http
          .put(uri, headers: headers, body: encodedBody)
          .timeout(_networkTimeout);
      final Map<String, dynamic> payload = _decodeJsonMap(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return payload;
      }

      final String message =
          _extractServerError(payload) ??
          'Profile update failed (${response.statusCode})';
      lastError = message;
      if (response.statusCode != 401 && response.statusCode != 403) {
        throw Exception(message);
      }
    }

    if (await refreshSession()) {
      final Map<String, String> refreshedHeaders = _authorizationHeaders(
        contentType: 'application/json',
      ).first;
      final http.Response retryResp = await http
          .put(uri, headers: refreshedHeaders, body: encodedBody)
          .timeout(_networkTimeout);
      final Map<String, dynamic> retryPayload = _decodeJsonMap(retryResp.body);
      if (retryResp.statusCode >= 200 && retryResp.statusCode < 300) {
        return retryPayload;
      }
    }
    throw Exception(lastError ?? 'Authentication failed for PUT $uri');
  }

  Future<Map<String, dynamic>> authorizedPostJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    return _authorizedPostJson(uri, body);
  }

  Future<Map<String, dynamic>> _authorizedPostJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final List<Map<String, String>> authHeaders = _authorizationHeaders(
      contentType: 'application/json',
    );

    String? lastError;
    final String encodedBody = jsonEncode(body);
    for (final Map<String, String> headers in authHeaders) {
      final http.Response response = await http
          .post(uri, headers: headers, body: encodedBody)
          .timeout(_networkTimeout);
      final Map<String, dynamic> payload = _decodeJsonMap(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return payload;
      }

      final String message =
          _extractServerError(payload) ??
          'Request failed (${response.statusCode})';
      lastError = message;
      if (response.statusCode != 401 && response.statusCode != 403) {
        throw Exception(message);
      }
    }

    if (await refreshSession()) {
      final Map<String, String> refreshedHeaders = _authorizationHeaders(
        contentType: 'application/json',
      ).first;
      final http.Response retryResp = await http
          .post(uri, headers: refreshedHeaders, body: encodedBody)
          .timeout(_networkTimeout);
      final Map<String, dynamic> retryPayload = _decodeJsonMap(retryResp.body);
      if (retryResp.statusCode >= 200 && retryResp.statusCode < 300) {
        return retryPayload;
      }
    }
    throw Exception(lastError ?? 'Authentication failed for POST $uri');
  }

  Future<Map<String, dynamic>> authorizedGet(Uri uri) async {
    final List<Map<String, String>> authHeaders = _authorizationHeaders();
    String? lastError;

    for (final Map<String, String> headers in authHeaders) {
      final http.Response response = await http
          .get(uri, headers: headers)
          .timeout(_networkTimeout);

      final Map<String, dynamic> payload = _decodeJsonMap(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return payload;
      }

      final String message =
          _extractServerError(payload) ??
          'Request failed (${response.statusCode})';
      lastError = message;
      if (response.statusCode != 401 && response.statusCode != 403) {
        throw Exception(message);
      }
    }

    if (await refreshSession()) {
      final Map<String, String> refreshedHeaders =
          _authorizationHeaders().first;
      final http.Response retryResp = await http
          .get(uri, headers: refreshedHeaders)
          .timeout(_networkTimeout);
      final Map<String, dynamic> retryPayload = _decodeJsonMap(retryResp.body);
      if (retryResp.statusCode >= 200 && retryResp.statusCode < 300) {
        return retryPayload;
      }
    }
    throw Exception(lastError ?? 'Authentication failed for GET $uri');
  }

  Future<Map<String, dynamic>> _authorizedUploadFile({
    required Uri uri,
    required String filePath,
    required Map<String, String> fields,
  }) async {
    final List<Map<String, String>> authHeaders = _authorizationHeaders();

    String? lastError;
    for (final Map<String, String> headers in authHeaders) {
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(headers)
        ..fields.addAll(fields)
        ..files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamed = await request.send().timeout(_networkTimeout);
      final response = await http.Response.fromStream(streamed);
      final payload = _decodeJsonMap(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return payload;
      }

      final String message =
          _extractServerError(payload) ??
          'Image upload failed (${response.statusCode})';
      lastError = message;
      if (response.statusCode != 401 && response.statusCode != 403) {
        throw Exception(message);
      }
    }

    if (await refreshSession()) {
      final Map<String, String> refreshedHeaders =
          _authorizationHeaders().first;
      final retryRequest = http.MultipartRequest('POST', uri)
        ..headers.addAll(refreshedHeaders)
        ..fields.addAll(fields)
        ..files.add(await http.MultipartFile.fromPath('file', filePath));
      final retryStreamed = await retryRequest.send().timeout(_networkTimeout);
      final retryResp = await http.Response.fromStream(retryStreamed);
      final retryPayload = _decodeJsonMap(retryResp.body);
      if (retryResp.statusCode >= 200 && retryResp.statusCode < 300) {
        return retryPayload;
      }
    }
    throw Exception(lastError ?? 'Authentication failed for POST $uri');
  }

  Future<Map<String, dynamic>> _authorizedUploadFileWithRetry({
    required Uri uri,
    required String filePath,
    required String fileName,
    required Map<String, String> fields,
  }) async {
    final List<Map<String, String>> authHeaders = _authorizationHeaders();

    String? lastError;
    for (final Map<String, String> headers in authHeaders) {
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(headers)
        ..fields.addAll(fields)
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            filePath,
            filename: fileName,
          ),
        );

      final streamed = await request.send().timeout(_networkTimeout);
      final response = await http.Response.fromStream(streamed);
      final payload = _decodeJsonMap(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return payload;
      }

      lastError =
          _extractServerError(payload) ??
          'Image upload failed (${response.statusCode})';

      // Only retry for auth errors
      if (response.statusCode != 401 && response.statusCode != 403) {
        throw Exception(lastError);
      }
    }

    if (await refreshSession()) {
      final Map<String, String> refreshedHeaders =
          _authorizationHeaders().first;
      final retryRequest = http.MultipartRequest('POST', uri)
        ..headers.addAll(refreshedHeaders)
        ..fields.addAll(fields)
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            filePath,
            filename: fileName,
          ),
        );
      final retryStreamed = await retryRequest.send().timeout(_networkTimeout);
      final retryResp = await http.Response.fromStream(retryStreamed);
      final retryPayload = _decodeJsonMap(retryResp.body);
      if (retryResp.statusCode >= 200 && retryResp.statusCode < 300) {
        return retryPayload;
      }
    }
    throw Exception(lastError ?? 'Authentication failed');
  }

  Future<Map<String, dynamic>> _authorizedPostFormWithRetry({
    required Uri uri,
    required Map<String, String> body,
  }) async {
    final List<Map<String, String>> authHeaders = _authorizationHeaders();

    String? lastError;
    for (final Map<String, String> headers in authHeaders) {
      final http.Response response = await http
          .post(uri, headers: headers, body: body)
          .timeout(_networkTimeout);

      final payload = _decodeJsonMap(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return payload;
      }

      lastError =
          _extractServerError(payload) ??
          'Request failed (${response.statusCode})';

      // Only retry for auth errors
      if (response.statusCode != 401 && response.statusCode != 403) {
        throw Exception(lastError);
      }
    }

    if (await refreshSession()) {
      final Map<String, String> refreshedHeaders =
          _authorizationHeaders().first;
      final http.Response retryResp = await http
          .post(uri, headers: refreshedHeaders, body: body)
          .timeout(_networkTimeout);
      final retryPayload = _decodeJsonMap(retryResp.body);
      if (retryResp.statusCode >= 200 && retryResp.statusCode < 300) {
        return retryPayload;
      }
    }
    throw Exception(lastError ?? 'Authentication failed');
  }

  String? _extractUploadedFileUrl(Map<String, dynamic> payload) {
    final dynamic message = payload['message'];
    if (message is Map<String, dynamic>) {
      return _nullIfBlank(
        message['file_url']?.toString() ?? message['file_name']?.toString(),
      );
    }

    final dynamic data = payload['data'];
    if (data is Map<String, dynamic>) {
      return _nullIfBlank(
        data['file_url']?.toString() ?? data['file_name']?.toString(),
      );
    }
    return null;
  }

  Future<String?> _resolveEmployeeNameForProfileSync() async {
    if (_loggedProfileDetails?.driver == null) {
      await fetchLoggedInEmployeeDriverProfile(forceRefresh: true);
    }

    return _nullIfBlank(_loggedProfileDetails?.employee?['name']?.toString()) ??
        _nullIfBlank(_loggedProfileDetails?.driver?['employee']?.toString());
  }

  Future<void> _updateEmployeeImage({
    required String employeeName,
    required String imageUrl,
  }) async {
    final Uri employeeUri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/resource/Employee/${Uri.encodeComponent(employeeName)}',
    );
    final Map<String, dynamic> payload = await authorizedPutJson(
      employeeUri,
      <String, dynamic>{'image': imageUrl},
    );
    final Map<String, dynamic>? refreshedEmployee = _extractResourceData(
      payload,
    );
    _loggedProfileDetails = LoggedPartnerProfileDetails(
      loggedUser: _loggedProfileDetails?.loggedUser,
      employee: refreshedEmployee ?? _loggedProfileDetails?.employee,
      driver: _loggedProfileDetails?.driver,
    );
  }

  Future<void> _persistServerProfileImageUrl(String? url) async {
    _serverProfileImageUrl = _nullIfBlank(url);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (_serverProfileImageUrl != null) {
      await prefs.setString(
        _prefServerProfileImageUrl,
        _serverProfileImageUrl!,
      );
    } else {
      await prefs.remove(_prefServerProfileImageUrl);
    }
  }

  /// Tries three approaches to set User.user_image.
  /// Returns null on success, or the last error string if all fail.
  Future<String?> _syncUserImageField({
    required String? userName,
    required String? imageUrl,
  }) async {
    final String? effectiveUser = _nullIfBlank(userName);
    if (effectiveUser == null ||
        effectiveUser.toLowerCase() == 'administrator') {
      return 'Could not resolve Frappe user name — web sync skipped';
    }

    final String value = imageUrl ?? '';

    // Approach 1: PUT /api/resource/User/{name}
    try {
      final Uri userUri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/resource/User/${Uri.encodeComponent(effectiveUser)}',
      );
      await authorizedPutJson(userUri, <String, dynamic>{'user_image': value});
      return null;
    } catch (_) {
    }

    // Approach 2: frappe.client.set_value with JSON body
    try {
      final Uri uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/method/frappe.client.set_value',
      );
      await authorizedPostJson(uri, <String, dynamic>{
        'doctype': 'User',
        'name': effectiveUser,
        'fieldname': 'user_image',
        'value': value,
      });
      return null;
    } catch (_) {
    }

    // Approach 3: frappe.client.set_value with form-encoded body
    // Some Frappe versions require multipart/form-data for whitelisted methods.
    try {
      final List<Map<String, String>> authHeaders = _authorizationHeaders();
      final Map<String, String> headers = authHeaders.isNotEmpty
          ? authHeaders.first
          : <String, String>{};
      final Uri uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/method/frappe.client.set_value',
      );
      final http.Response response = await http
          .post(
            uri,
            headers: headers,
            body: <String, String>{
              'doctype': 'User',
              'name': effectiveUser,
              'fieldname': 'user_image',
              'value': value,
            },
          )
          .timeout(_networkTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return null;
      }
      final String formErr =
          _extractServerError(_decodeJsonMap(response.body)) ??
          'set_value form failed (${response.statusCode})';
      return 'user_image web sync failed: $formErr\n(User: $effectiveUser, URL: $value)';
    } catch (e) {
      final String msg = e.toString().replaceFirst('Exception: ', '');
      return 'user_image web sync failed: $msg\n(User: $effectiveUser, URL: $value)';
    }
  }

  Map<String, dynamic>? _extractResourceData(Map<String, dynamic> payload) {
    final dynamic data = payload['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    final dynamic message = payload['message'];
    if (message is Map<String, dynamic>) {
      return message;
    }
    return null;
  }

  Future<Map<String, dynamic>> _buildEmployeeProfileUpdatePayload({
    String? fullName,
    required String? email,
    String? mobile,
  }) async {
    final Map<String, String> employeeFields = await _fetchDoctypeFieldTypes(
      'Employee',
    );
    final Map<String, dynamic> payload = <String, dynamic>{};

    void setIfEditable(String fieldname, dynamic value) {
      if (!employeeFields.containsKey(fieldname)) {
        return;
      }
      payload[fieldname] = value;
    }

    if (fullName != null) {
      setIfEditable('employee_name', fullName);
      final List<String> nameParts = fullName
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList();
      if (nameParts.isNotEmpty) {
        setIfEditable('first_name', nameParts.first);
        if (nameParts.length > 1) {
          setIfEditable('last_name', nameParts.skip(1).join(' '));
        } else {
          setIfEditable('last_name', '');
        }
      }
    }

    if (mobile != null) {
      if (employeeFields.containsKey('cell_number')) {
        payload['cell_number'] = mobile;
      } else if (employeeFields.containsKey('mobile_no')) {
        payload['mobile_no'] = mobile;
      }
    }

    if (email != null) {
      if (employeeFields.containsKey('personal_email')) {
        payload['personal_email'] = email;
      } else if (employeeFields.containsKey('company_email')) {
        payload['company_email'] = email;
      } else if (employeeFields.containsKey('email')) {
        payload['email'] = email;
      }
    }

    return payload;
  }

  String? _resolveUserNameForProfileSync() {
    return _nullIfBlank(
          _loggedProfileDetails?.driver?['user_id']?.toString(),
        ) ??
        _nullIfBlank(_loggedProfileDetails?.loggedUser);
  }

  Future<void> _updateUserProfileAndMaybeRename({
    required String currentUserName,
    String? fullName,
    String? email,
    String? mobile,
  }) async {
    String effectiveUserName = currentUserName;

    if (email != null &&
        email.isNotEmpty &&
        currentUserName.toLowerCase() != email.toLowerCase()) {
      final Uri renameUri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/method/frappe.client.rename_doc',
      );
      await authorizedPostJson(renameUri, <String, dynamic>{
        'doctype': 'User',
        'old_name': currentUserName,
        'new_name': email,
        'merge': false,
      });
      effectiveUserName = email;
    }

    final Map<String, String> userFields = await _fetchDoctypeFieldTypes(
      'User',
    );
    final Map<String, dynamic> payload = <String, dynamic>{};

    if (fullName != null) {
      final List<String> nameParts = fullName
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList();
      if (userFields.containsKey('full_name')) {
        payload['full_name'] = fullName;
      }
      if (nameParts.isNotEmpty) {
        if (userFields.containsKey('first_name')) {
          payload['first_name'] = nameParts.first;
        }
        if (userFields.containsKey('last_name')) {
          payload['last_name'] = nameParts.length > 1
              ? nameParts.skip(1).join(' ')
              : '';
        }
      }
    }

    if (email != null) {
      if (userFields.containsKey('username')) {
        payload['username'] = email;
      }
      if (userFields.containsKey('email')) {
        payload['email'] = email;
      }
    }

    if (mobile != null && userFields.containsKey('mobile_no')) {
      payload['mobile_no'] = mobile;
    }

    if (payload.isEmpty) {
      _loggedProfileDetails = LoggedPartnerProfileDetails(
        loggedUser: effectiveUserName,
        employee: _loggedProfileDetails?.employee,
        driver: _loggedProfileDetails?.driver,
      );
      return;
    }

    final Uri userUri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/resource/User/${Uri.encodeComponent(effectiveUserName)}',
    );
    await authorizedPutJson(userUri, payload);
    _loggedProfileDetails = LoggedPartnerProfileDetails(
      loggedUser: effectiveUserName,
      employee: _loggedProfileDetails?.employee,
      driver: _loggedProfileDetails?.driver,
    );
  }

  Future<Map<String, String>> _fetchDoctypeFieldTypes(String doctype) async {
    try {
      final Uri uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/resource/DocType/${Uri.encodeComponent(doctype)}',
      );
      final Map<String, dynamic> payload = await _authorizedGet(uri);
      final dynamic data = payload['data'];
      if (data is! Map<String, dynamic>) {
        return <String, String>{};
      }
      final dynamic fields = data['fields'];
      if (fields is! List) {
        return <String, String>{};
      }

      final Map<String, String> fieldTypes = <String, String>{};
      for (final dynamic row in fields) {
        if (row is! Map<String, dynamic>) {
          continue;
        }
        final String? fieldname = _nullIfBlank(row['fieldname']?.toString());
        final String? fieldtype = _nullIfBlank(row['fieldtype']?.toString());
        final int readOnly =
            int.tryParse(row['read_only']?.toString() ?? '0') ?? 0;
        if (fieldname == null || fieldtype == null || readOnly == 1) {
          continue;
        }
        fieldTypes[fieldname] = fieldtype;
      }
      return fieldTypes;
    } catch (_) {
      return <String, String>{};
    }
  }

  /// Returns the primary auth header for use outside AppController (e.g. image loading).
  /// Result is cached per token value — safe to call on every rebuild.
  Map<String, String> buildAuthHeaders() {
    final key = '${_tokenType}_${_sessionToken ?? ''}';
    if (_cachedAuthHeaders != null && _cachedAuthHeadersKey == key) {
      return _cachedAuthHeaders!;
    }
    final headers = _authorizationHeaders();
    _cachedAuthHeaders = headers.isNotEmpty ? headers.first : const <String, String>{};
    _cachedAuthHeadersKey = key;
    return _cachedAuthHeaders!;
  }

  List<Map<String, String>> _authorizationHeaders({String? contentType}) {
    final List<Map<String, String>> authHeaders = <Map<String, String>>[];
    if (_sessionToken != null && _sessionToken!.trim().isNotEmpty) {
      final Map<String, String> bearerHeaders = <String, String>{
        'Accept': 'application/json',
        'Accept-Language': _languageHeaderValue(),
        'Authorization': '${_tokenType.trim()} ${_sessionToken!.trim()}',
      };
      if (contentType != null) {
        bearerHeaders['Content-Type'] = contentType;
      }
      authHeaders.add(bearerHeaders);
    }
    if (_sessionToken != null && _sessionToken!.trim().isNotEmpty) {
      final String altType = _tokenType.trim().toLowerCase() == 'token'
          ? 'Bearer'
          : 'token';
      final Map<String, String> tokenHeaders = <String, String>{
        'Accept': 'application/json',
        'Accept-Language': _languageHeaderValue(),
        'Authorization': '$altType ${_sessionToken!.trim()}',
      };
      if (contentType != null) {
        tokenHeaders['Content-Type'] = contentType;
      }
      authHeaders.add(tokenHeaders);
    }
    return authHeaders;
  }

  Map<String, String> _requestHeaders({String? contentType}) {
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Accept-Language': _languageHeaderValue(),
    };
    if (contentType != null) {
      headers['Content-Type'] = contentType;
    }
    return headers;
  }

  String _languageHeaderValue() {
    final String language = _languageCode.isEmpty ? 'en' : _languageCode;
    return AppStrings.isSupportedLanguageCode(language) ? language : 'en';
  }

  String? _normalizedMobileForSearch(String? raw) {
    final String? value = _nullIfBlank(raw);
    if (value == null) {
      return null;
    }
    final String digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }
    if (digits.length == 10) {
      return digits;
    }
    return null;
  }

  VehicleDetails _vehicleFromApiData(Map<String, dynamic> data) {
    final int? odometer = _nullableInt(data['last_odometer']?.toString());
    final int? wheels = _nullableInt(data['wheels']?.toString());
    final int? doors = _nullableInt(data['doors']?.toString());
    final double? vehicleValue = _nullableDouble(
      data['vehicle_value']?.toString(),
    );

    return VehicleDetails(
      name: _nullIfBlank(data['name']?.toString()),
      licensePlate: _nullIfBlank(data['license_plate']?.toString()) ?? '',
      make: _nullIfBlank(data['make']?.toString()) ?? '',
      model: _nullIfBlank(data['model']?.toString()) ?? '',
      lastOdometer: odometer ?? 0,
      fuelType: _nullIfBlank(data['fuel_type']?.toString()) ?? '',
      uom: _nullIfBlank(data['uom']?.toString()) ?? '',
      acquisitionDate: _nullIfBlank(data['acquisition_date']?.toString()),
      location: _nullIfBlank(data['location']?.toString()),
      chassisNo: _nullIfBlank(data['chassis_no']?.toString()),
      vehicleValue: vehicleValue,
      employee: _nullIfBlank(data['employee']?.toString()),
      insuranceCompany: _nullIfBlank(data['insurance_company']?.toString()),
      policyNo: _nullIfBlank(data['policy_no']?.toString()),
      startDate: _nullIfBlank(data['start_date']?.toString()),
      endDate: _nullIfBlank(data['end_date']?.toString()),
      carbonCheckDate: _nullIfBlank(data['carbon_check_date']?.toString()),
      color: _nullIfBlank(data['color']?.toString()),
      wheels: wheels,
      doors: doors,
      status: VerificationStatus.approved,
    );
  }

  BankDetails _bankFromApiData(Map<String, dynamic> data) {
    return BankDetails(
      accountNumber:
          _nullIfBlank(data['bank_account_no']?.toString()) ??
          _nullIfBlank(data['account_name']?.toString()) ??
          '',
      ifsc:
          _nullIfBlank(data['branch_code']?.toString()) ??
          _nullIfBlank(data['ifsc']?.toString()) ??
          '',
      accountHolder: _nullIfBlank(data['account_name']?.toString()) ?? '',
      upiId: _nullIfBlank(data['iban']?.toString()),
      verified: true,
    );
  }

  Future<void> _persistVehicleIdentity({
    String? vehicleName,
    String? licensePlate,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<Future<bool>> writes = <Future<bool>>[];
    if (_nullIfBlank(vehicleName) != null) {
      writes.add(prefs.setString(_prefVehicleName, vehicleName!.trim()));
    }
    if (_nullIfBlank(licensePlate) != null) {
      writes.add(
        prefs.setString(_prefVehicleLicensePlate, licensePlate!.trim()),
      );
    }
    if (writes.isNotEmpty) {
      await Future.wait(writes);
    }
  }

  Future<void> _persistBankIdentity({
    String? bankDocName,
    String? accountName,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<Future<bool>> writes = <Future<bool>>[];
    if (_nullIfBlank(bankDocName) != null) {
      writes.add(prefs.setString(_prefBankDocName, bankDocName!.trim()));
    }
    if (_nullIfBlank(accountName) != null) {
      writes.add(prefs.setString(_prefBankAccountName, accountName!.trim()));
    }
    if (writes.isNotEmpty) {
      await Future.wait(writes);
    }
  }

  int? _nullableInt(String? value) {
    final String? normalized = _nullIfBlank(value);
    if (normalized == null) {
      return null;
    }
    return int.tryParse(normalized);
  }

  double? _nullableDouble(String? value) {
    final String? normalized = _nullIfBlank(value);
    if (normalized == null) {
      return null;
    }
    return double.tryParse(normalized);
  }
}
