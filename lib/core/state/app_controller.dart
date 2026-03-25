import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';

class AppController extends ChangeNotifier {
  static const String _storeId = 'GROZFY';
  static final Uri _sendOtpUri = Uri.parse(
    'https://grozfy.com/api/method/frappe.core.api.billing_auth_v4.send_whatsapp_otp',
  );
  static final Uri _verifyOtpUri = Uri.parse(
    'https://grozfy.com/api/method/frappe.core.api.billing_auth_v4.verify_whatsapp_otp',
  );
  static const String _prefLanguageCode = 'language_code';
  static const String _prefAccessToken = 'access_token';
  static const String _prefRefreshToken = 'refresh_token';
  static const String _prefTokenType = 'token_type';
  static const String _prefExpiresIn = 'expires_in';
  static const String _prefMobile = 'partner_mobile';
  static const String _prefEmail = 'partner_email';
  static const String _prefFullName = 'partner_full_name';
  static const String _prefRememberMe = 'remember_me';
  static const String _prefCurrentLat = 'current_lat';
  static const String _prefCurrentLng = 'current_lng';
  static const String _prefCurrentLocationLabel = 'current_location_label';
  static const String _prefProfileCompleted = 'profile_completed';

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
  String? _sessionToken;
  String? _configVersion;

  DateTime? _lastOtpRequestAt;

  PartnerProfile? _profile;
  VehicleDetails? _vehicle;
  BankDetails? _bank;
  bool _rcUploaded = false;
  PermissionState _permissionState = const PermissionState();

  bool _isOnline = false;
  bool _isTracking = false;
  int _trackingInterval = 10;
  String _liveCoordinates = '28.6139, 77.2090';
  double? _currentLatitude;
  double? _currentLongitude;
  String? _currentLocationLabel;

  DeliveryOrder? _incomingOrder;
  DeliveryOrder? _activeOrder;
  final List<DeliveryOrder> _availableOrders = <DeliveryOrder>[];
  final List<DeliveryOrder> _acceptedOrders = <DeliveryOrder>[];
  bool _isLoadingOrders = false;
  String? _orderLoadingError;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);
  Timer? _liveLocationTimer;
  GeoLocation? _partnerLiveLocation;

  EarningsSummary _earnings = const EarningsSummary(
    today: 1250,
    week: 7120,
    total: 86750,
    pendingPayout: 960,
  );

  PerformanceMetrics _performance = const PerformanceMetrics(
    rating: 4.8,
    acceptanceRate: 86,
    completionRate: 94,
    totalDeliveries: 412,
  );

  bool get bootstrapped => _bootstrapped;
  bool get isLoggedIn => _isLoggedIn;
  bool get rememberMe => _rememberMe;
  bool get profileCompleted => _profileCompleted;
  String get languageCode => _languageCode;
  String? get configVersion => _configVersion;
  PartnerProfile? get profile => _profile;
  Map<String, VerificationStatus> get kycStatus => _kycStatus;
  Map<String, double> get kycProgress => _kycProgress;
  VehicleDetails? get vehicle => _vehicle;
  BankDetails? get bank => _bank;
  bool get rcUploaded => _rcUploaded;
  PermissionState get permissionState => _permissionState;
  bool get isOnline => _isOnline;
  bool get isTracking => _isTracking;
  int get trackingInterval => _trackingInterval;
  String get liveCoordinates => _liveCoordinates;
  double? get currentLatitude => _currentLatitude;
  double? get currentLongitude => _currentLongitude;
  String? get currentLocationLabel => _currentLocationLabel;
  bool get hasSelectedLocation =>
      _currentLatitude != null && _currentLongitude != null;
  DeliveryOrder? get incomingOrder => _incomingOrder;
  DeliveryOrder? get activeOrder => _activeOrder;
  EarningsSummary get earnings => _earnings;
  PerformanceMetrics get performance => _performance;
  List<AppNotice> get notices => List<AppNotice>.unmodifiable(_notices);

  bool get allKycApproved => _kycStatus.values.every(
    (status) => status == VerificationStatus.approved,
  );

  bool get canGoOnline =>
      allKycApproved &&
      _vehicle?.status == VerificationStatus.approved &&
      (_bank?.verified ?? false) &&
      hasSelectedLocation &&
      _permissionState.allGranted;

  Future<void> bootstrap() async {
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    _configVersion = 'cfg_2026_02_16';

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _languageCode = prefs.getString(_prefLanguageCode) ?? '';
    _sessionToken = prefs.getString(_prefAccessToken);
    _rememberMe = prefs.getBool(_prefRememberMe) ?? false;
    _profileCompleted = prefs.getBool(_prefProfileCompleted) ?? false;
    _currentLatitude = prefs.getDouble(_prefCurrentLat);
    _currentLongitude = prefs.getDouble(_prefCurrentLng);
    _currentLocationLabel = _nullIfBlank(
      prefs.getString(_prefCurrentLocationLabel),
    );
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

    _bootstrapped = true;
    notifyListeners();
  }

  void setLanguage(String code) {
    _languageCode = code;
    _writePref((SharedPreferences prefs) {
      return prefs.setString(_prefLanguageCode, code);
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

  Future<void> updateProfile({String? fullName, String? email}) async {
    if (_profile != null) {
      _profile = _profile!.copyWith(fullName: fullName, email: email);
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

  String? validateMobile(String mobile) {
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(mobile.trim())) {
      return 'Enter a valid 10-digit mobile number';
    }
    return null;
  }

  Future<String> sendOtp(String mobile) async {
    final String? mobileValidation = validateMobile(mobile);
    if (mobileValidation != null) {
      return mobileValidation;
    }

    final DateTime now = DateTime.now();
    if (_lastOtpRequestAt != null) {
      final int elapsed = now.difference(_lastOtpRequestAt!).inSeconds;
      if (elapsed < 30) {
        return 'OTP is rate-limited. Try again in ${30 - elapsed}s';
      }
    }

    try {
      _logApi(
        'send_whatsapp_otp request',
        <String, String>{
          'mobile_no': mobile.trim(),
          'store_id': _storeId,
        }.toString(),
      );
      final http.Response response = await http.post(
        _sendOtpUri,
        headers: const <String, String>{'Accept': 'application/json'},
        body: <String, String>{
          'mobile_no': mobile.trim(),
          'store_id': _storeId,
        },
      );
      _logApi(
        'send_whatsapp_otp response',
        'status=${response.statusCode} body=${response.body}',
      );

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

      _lastOtpRequestAt = now;
      return 'OTP sent successfully to $mobile';
    } catch (e) {
      _logApi('send_whatsapp_otp error', e.toString());
      return 'Unable to connect. Check internet and try again.';
    }
  }

  bool verifyOtp(String mobile, String otp) =>
      otp.isNotEmpty && mobile.isNotEmpty;

  Future<String?> loginWithPassword({
    required String mobile,
    required String password,
  }) async {
    final String? mobileValidation = validateMobile(mobile);
    if (mobileValidation != null) {
      return mobileValidation;
    }
    if (password.trim().length < 6) {
      return 'Password must be at least 6 characters';
    }

    return 'Password login is not configured for this API. Use OTP login.';
  }

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
      _logApi(
        'verify_whatsapp_otp request',
        <String, String>{
          'mobile_no': mobile.trim(),
          'otp': otp.trim(),
          'store_id': _storeId,
        }.toString(),
      );
      final http.Response response = await http.post(
        _verifyOtpUri,
        headers: const <String, String>{'Accept': 'application/json'},
        body: <String, String>{
          'mobile_no': mobile.trim(),
          'otp': otp.trim(),
          'store_id': _storeId,
        },
      );
      _logApi(
        'verify_whatsapp_otp response',
        'status=${response.statusCode} body=${response.body}',
      );

      final Map<String, dynamic> payload = _decodeJsonMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _extractServerError(payload) ??
            'OTP verification failed (${response.statusCode})';
      }

      final String? possibleError = _extractServerError(payload);
      if (possibleError != null) {
        return possibleError;
      }

      final Map<String, dynamic> responseData = _extractMethodData(payload);
      final String status = (responseData['status']?.toString() ?? '')
          .toLowerCase();
      if (status.isNotEmpty && status != 'success') {
        return _nullIfBlank(responseData['message']?.toString()) ??
            'OTP verification failed';
      }

      final String token = responseData['access_token']?.toString() ?? '';
      if (token.isEmpty) {
        return 'Access token missing in verify response';
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
      _currentLatitude = null;
      _currentLongitude = null;
      _currentLocationLabel = null;
      _profile = PartnerProfile(
        fullName: fullName,
        mobile: responseMobile,
        email: email,
      );

      await _persistSession(responseData);
      notifyListeners();
      return null;
    } catch (e) {
      _logApi('verify_whatsapp_otp error', e.toString());
      return 'Unable to connect. Check internet and try again.';
    }
  }

  Future<String?> registerPartner({
    required String fullName,
    required String mobile,
    required String password,
    required String otp,
    String? email,
    String? referralCode,
  }) async {
    if (fullName.trim().isEmpty) {
      return 'Full name is required';
    }

    final String? mobileValidation = validateMobile(mobile);
    if (mobileValidation != null) {
      return mobileValidation;
    }

    if (password.trim().length < 6) {
      return 'Password must be at least 6 characters';
    }

    final String? verifyError = await loginWithOtp(mobile: mobile, otp: otp);
    if (verifyError != null) {
      return verifyError;
    }

    _profile = _profile?.copyWith(
      fullName: fullName.trim(),
      email: email?.trim().isEmpty == true ? null : email?.trim(),
      referralCode: referralCode?.trim().isEmpty == true
          ? null
          : referralCode?.trim(),
    );
    notifyListeners();
    return null;
  }

  Future<void> logout() async {
    _isLoggedIn = false;
    _sessionToken = null;
    _isOnline = false;
    _isTracking = false;
    _incomingOrder = null;
    _activeOrder = null;
    _profile = null;
    _profileCompleted = false;
    _currentLatitude = null;
    _currentLongitude = null;
    _currentLocationLabel = null;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      prefs.remove(_prefAccessToken),
      prefs.remove(_prefRefreshToken),
      prefs.remove(_prefTokenType),
      prefs.remove(_prefExpiresIn),
      prefs.remove(_prefFullName),
      prefs.remove(_prefEmail),
      prefs.remove(_prefMobile),
      prefs.remove(_prefCurrentLat),
      prefs.remove(_prefCurrentLng),
      prefs.remove(_prefCurrentLocationLabel),
      prefs.remove(_prefProfileCompleted),
      prefs.setBool(_prefRememberMe, false),
    ]);
    _rememberMe = false;
    notifyListeners();
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

  void simulateKycApproval() {
    for (final String key in _kycStatus.keys) {
      _kycStatus[key] = VerificationStatus.approved;
      _kycProgress[key] = 1;
    }
    _vehicle = _vehicle == null
        ? null
        : VehicleDetails(
            type: _vehicle!.type,
            vehicleNumber: _vehicle!.vehicleNumber,
            rcUploaded: _vehicle!.rcUploaded,
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

  String? submitVehicleDetails({
    required VehicleType type,
    required String vehicleNumber,
  }) {
    final String sanitized = vehicleNumber.trim().toUpperCase();
    final RegExp regExp = RegExp(
      r'^[A-Z]{2}[\s-]?[0-9]{1,2}[\s-]?[A-Z]{1,2}[\s-]?[0-9]{4}$',
    );

    if (!regExp.hasMatch(sanitized)) {
      return 'Vehicle number format is invalid';
    }

    if (!_rcUploaded) {
      return 'Upload RC document first';
    }

    _vehicle = VehicleDetails(
      type: type,
      vehicleNumber: sanitized,
      rcUploaded: true,
      status: VerificationStatus.pending,
    );
    notifyListeners();
    return null;
  }

  Future<void> uploadRcDocument() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _rcUploaded = true;
    notifyListeners();
  }

  String? submitBankDetails({
    required String accountNumber,
    required String ifsc,
    required String accountHolder,
    String? upiId,
  }) {
    final String normalizedAccount = accountNumber.trim();
    if (!RegExp(r'^\d{9,18}$').hasMatch(normalizedAccount)) {
      return 'Account number should be 9-18 digits';
    }

    final String normalizedIfsc = ifsc.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(normalizedIfsc)) {
      return 'IFSC format is invalid';
    }

    if (accountHolder.trim().isEmpty) {
      return 'Account holder name is required';
    }

    _bank = BankDetails(
      accountNumber: normalizedAccount,
      ifsc: normalizedIfsc,
      accountHolder: accountHolder.trim(),
      upiId: upiId?.trim().isEmpty == true ? null : upiId?.trim(),
      verified: true,
    );
    notifyListeners();
    return null;
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
    notifyListeners();
  }

  void setTrackingInterval(int seconds) {
    _trackingInterval = seconds;
    notifyListeners();
  }

  String? setOnline(bool value) {
    if (value && !canGoOnline) {
      return 'Complete KYC, bank setup, location selection, and permissions before going online';
    }

    _isOnline = value;
    if (_isOnline) {
      startTracking();
      _notices.insert(
        0,
        AppNotice(
          title: 'You are online',
          message: 'Nearby orders will now be assigned to you.',
          time: DateTime.now(),
        ),
      );
    } else {
      stopTracking();
    }

    notifyListeners();
    return null;
  }

  String? startTracking() {
    if (!_permissionState.allGranted) {
      return 'Location and notification permissions are required';
    }
    _isTracking = true;
    _updateLiveCoordinates();
    notifyListeners();
    return null;
  }

  void stopTracking() {
    _isTracking = false;
    notifyListeners();
  }

  void tickLocation() {
    if (!_isTracking) {
      return;
    }
    _updateLiveCoordinates();
    notifyListeners();
  }

  DeliveryOrder generateIncomingOrder() {
    final String orderId = '#OD${1000 + _random.nextInt(8999)}';
    _incomingOrder = DeliveryOrder(
      orderId: orderId,
      customerName: 'Riya Sharma',
      customerPhone: '9876501234',
      deliveryAddress: 'Karol Bagh, New Delhi - 110005',
      storeId: 'STORE${100 + _random.nextInt(899)}',
      storeName: 'Fresh Bites Kitchen',
      storeContact: '9876543210',
      storeAddress: 'Connaught Place, New Delhi - 110001',
      orderItems: <OrderItem>[
        const OrderItem(name: 'Veg Biryani', quantity: 2, price: 180),
        const OrderItem(name: 'Chicken Curry', quantity: 1, price: 250),
        const OrderItem(name: 'Naan', quantity: 4, price: 40),
      ],
      orderStatus: OrderStatus.pending,
      latitude: 28.6692 + (_random.nextDouble() - 0.5) * 0.1,
      longitude: 77.4538 + (_random.nextDouble() - 0.5) * 0.1,
      pickup: 'Connaught Place, New Delhi',
      drop: 'Karol Bagh, New Delhi',
      deliveryInstructions: 'Call before arrival, gate code 2456',
      paymentMode: _random.nextBool() ? 'COD' : 'Online',
      distanceKm: 6.4,
      estimatedEarnings: 132,
      assignmentStatus: OrderAssignmentStatus.unassigned,
    );
    notifyListeners();
    return _incomingOrder!;
  }

  void respondToOrderRequest({required bool accept}) {
    if (_incomingOrder == null) {
      return;
    }

    if (accept) {
      _activeOrder = _incomingOrder;
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
    notifyListeners();
  }

  void updateOrderStatus(OrderProgressStatus status) {
    if (_activeOrder == null) {
      return;
    }

    _activeOrder = _activeOrder!.copyWith(orderStatus: status);

    if (status == OrderStatus.delivered) {
      final double payout = _activeOrder!.estimatedEarnings;
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
          message: 'Order ${_activeOrder!.orderId} delivered successfully.',
          time: DateTime.now(),
        ),
      );
      _activeOrder = null;
    }

    notifyListeners();
  }

  List<DeliveryOrder> get availableOrders =>
      List<DeliveryOrder>.unmodifiable(_availableOrders);

  List<DeliveryOrder> get acceptedOrders =>
      List<DeliveryOrder>.unmodifiable(_acceptedOrders);

  bool get isLoadingOrders => _isLoadingOrders;

  String? get orderLoadingError => _orderLoadingError;

  GeoLocation? get partnerLiveLocation => _partnerLiveLocation;

  Future<void> fetchAvailableOrders() async {
    _isLoadingOrders = true;
    _orderLoadingError = null;
    notifyListeners();

    try {
      await _fetchOrdersWithRetry();
    } catch (e) {
      _orderLoadingError = 'Failed to fetch orders: $e';
    } finally {
      _isLoadingOrders = false;
      notifyListeners();
    }
  }

  Future<void> _fetchOrdersWithRetry() async {
    _retryCount = 0;
    while (_retryCount < _maxRetries) {
      try {
        await _fetchOrders();
        return;
      } catch (e) {
        _retryCount++;
        if (_retryCount >= _maxRetries) {
          rethrow;
        }
        await Future<void>.delayed(_retryDelay * _retryCount);
      }
    }
  }

  Future<void> _fetchOrders() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (_random.nextBool()) {
      throw Exception('Network error');
    }
    _availableOrders.clear();
    _availableOrders.addAll(_generateMockAvailableOrders());
    notifyListeners();
  }

  List<DeliveryOrder> _generateMockAvailableOrders() {
    final List<DeliveryOrder> orders = <DeliveryOrder>[];
    final List<String> customerNames = <String>[
      'Riya Sharma',
      'Amit Kumar',
      'Priya Singh',
      'Rahul Verma',
      'Sneha Gupta',
    ];
    final List<String> storeNames = <String>[
      'Fresh Bites Kitchen',
      'Tasty Treats',
      'Burger Barn',
      'Pizza Palace',
      'Sushi Station',
    ];
    final List<String> addresses = <String>[
      'Connaught Place, New Delhi',
      'Karol Bagh, New Delhi',
      'Lajpat Nagar, New Delhi',
      'Saket, New Delhi',
      'Dwarka, New Delhi',
    ];

    for (int i = 0; i < 5; i++) {
      orders.add(
        DeliveryOrder(
          orderId: '#OD${1000 + _random.nextInt(8999)}',
          customerName: customerNames[i],
          customerPhone: '98765${1000 + _random.nextInt(8999)}',
          deliveryAddress: '${addresses[i]} - ${110001 + i * 10}',
          storeId: 'STORE${100 + _random.nextInt(899)}',
          storeName: storeNames[i],
          storeContact: '98765${43210 + _random.nextInt(10000)}',
          storeAddress: addresses[(i + 2) % addresses.length],
          orderItems: <OrderItem>[
            OrderItem(
              name: 'Item ${i + 1}',
              quantity: 1 + _random.nextInt(3),
              price: (50 + _random.nextInt(200)).toDouble(),
            ),
            if (_random.nextBool())
              OrderItem(
                name: 'Drink ${i + 1}',
                quantity: 1,
                price: 30 + _random.nextInt(50).toDouble(),
              ),
          ],
          orderStatus: OrderStatus.pending,
          latitude: 28.6139 + (_random.nextDouble() - 0.5) * 0.2,
          longitude: 77.2090 + (_random.nextDouble() - 0.5) * 0.2,
          pickup: addresses[(i + 2) % addresses.length],
          drop: addresses[i],
          deliveryInstructions: _random.nextBool()
              ? 'Call before arrival'
              : 'Leave at door',
          paymentMode: _random.nextBool() ? 'COD' : 'Online',
          distanceKm: (3 + _random.nextDouble() * 7).roundToDouble(),
          estimatedEarnings: (50 + _random.nextInt(100)).toDouble(),
          assignmentStatus: OrderAssignmentStatus.unassigned,
        ),
      );
    }
    notifyListeners();
    return orders;
  }

  String? acceptOrder(String orderId) {
    final int index = _availableOrders.indexWhere(
      (order) => order.orderId == orderId,
    );
    if (index == -1) {
      return 'Order not found';
    }

    final DeliveryOrder order = _availableOrders[index];

    if (order.assignmentStatus == OrderAssignmentStatus.assigned) {
      return 'Order already assigned to another partner';
    }

    _availableOrders.removeAt(index);

    _activeOrder = order.copyWith(
      assignmentStatus: OrderAssignmentStatus.assigned,
      assignedDeliveryPartnerId: _profile?.mobile ?? 'PARTNER001',
      orderStatus: OrderStatus.accepted,
    );

    _acceptedOrders.add(_activeOrder!);

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

    notifyListeners();
    return null;
  }

  void rejectOrder(String orderId) {
    final int index = _availableOrders.indexWhere(
      (order) => order.orderId == orderId,
    );
    if (index != -1) {
      _availableOrders.removeAt(index);
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

    notifyListeners();
  }

  String? reachedPickup(String orderId) {
    if (_activeOrder == null || _activeOrder!.orderId != orderId) {
      return 'No active order found';
    }

    if (_activeOrder!.orderStatus != OrderStatus.accepted) {
      return 'Order must be accepted first';
    }

    _activeOrder = _activeOrder!.copyWith(
      orderStatus: OrderStatus.reachedPickup,
      reachedStoreAt: DateTime.now(),
      deliveryPartnerLocation:
          _partnerLiveLocation ??
          GeoLocation(
            latitude: _currentLatitude ?? 28.6139,
            longitude: _currentLongitude ?? 77.2090,
          ),
    );

    final int acceptedIndex = _acceptedOrders.indexWhere(
      (order) => order.orderId == orderId,
    );
    if (acceptedIndex != -1) {
      _acceptedOrders[acceptedIndex] = _activeOrder!;
    }

    _notices.insert(
      0,
      AppNotice(
        title: 'Store Notified',
        message: 'Store has been informed that you have arrived.',
        time: DateTime.now(),
      ),
    );

    notifyListeners();
    return null;
  }

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
  }

  void stopLiveLocationTracking() {
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;
  }

  void _updateLiveLocation() {
    final double baseLat = _currentLatitude ?? 28.6139;
    final double baseLng = _currentLongitude ?? 77.2090;
    _partnerLiveLocation = GeoLocation(
      latitude: baseLat + (_random.nextDouble() - 0.5) / 100,
      longitude: baseLng + (_random.nextDouble() - 0.5) / 100,
    );
    if (_activeOrder != null &&
        _activeOrder!.orderStatus == OrderStatus.reachedPickup) {
      _activeOrder = _activeOrder!.copyWith(
        deliveryPartnerLocation: _partnerLiveLocation,
      );
    }
    notifyListeners();
  }

  String t(String key) {
    const Map<String, Map<String, String>> dictionary = {
      'en': {
        'app_title': 'FlowFleet Partner',
        'login': 'Login',
        'register': 'Register',
        'dashboard': 'Dashboard',
      },
      'hi': {
        'app_title': 'FlowFleet पार्टनर',
        'login': 'लॉगिन',
        'register': 'रजिस्टर',
        'dashboard': 'डैशबोर्ड',
      },
    };

    final String selected = _languageCode.isEmpty ? 'en' : _languageCode;
    return dictionary[selected]?[key] ?? dictionary['en']![key] ?? key;
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
    final int? expiresIn = int.tryParse(
      message['expires_in']?.toString() ?? '',
    );

    await Future.wait(<Future<bool>>[
      prefs.setString(_prefAccessToken, _sessionToken!),
      prefs.setBool(_prefRememberMe, _rememberMe),
      prefs.remove(_prefCurrentLat),
      prefs.remove(_prefCurrentLng),
      prefs.remove(_prefCurrentLocationLabel),
      if (refreshToken != null)
        prefs.setString(_prefRefreshToken, refreshToken),
      if (tokenType != null) prefs.setString(_prefTokenType, tokenType),
      if (expiresIn != null) prefs.setInt(_prefExpiresIn, expiresIn),
      if (fullName != null) prefs.setString(_prefFullName, fullName),
      if (mobile != null) prefs.setString(_prefMobile, mobile),
      if (email != null) prefs.setString(_prefEmail, email),
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

  void _writePref(Future<bool> Function(SharedPreferences prefs) writer) {
    unawaited(() async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await writer(prefs);
    }());
  }

  void _logApi(String tag, String value) {
    debugPrint('[API] $tag => $value');
  }

  void _updateLiveCoordinates() {
    final double baseLat = 28.6139;
    final double baseLng = 77.2090;
    final double lat = baseLat + (_random.nextDouble() - 0.5) / 100;
    final double lng = baseLng + (_random.nextDouble() - 0.5) / 100;
    _liveCoordinates = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }
}
