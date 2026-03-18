import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/api_constants.dart';
import '../models/app_models.dart';

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
  static const String _prefLanguageCode = 'language_code';
  static const String _prefAccessToken = 'access_token';
  static const String _prefRefreshToken = 'refresh_token';
  static const String _prefTokenType = 'token_type';
  static const String _prefExpiresIn = 'expires_in';
  static const String _prefMobile = 'partner_mobile';
  static const String _prefEmail = 'partner_email';
  static const String _prefFullName = 'partner_full_name';
  static const String _prefProfileImagePath = 'partner_profile_image_path';
  static const String _prefRememberMe = 'remember_me';
  static const String _prefCurrentLat = 'current_lat';
  static const String _prefCurrentLng = 'current_lng';
  static const String _prefCurrentLocationLabel = 'current_location_label';
  static const String _prefSelectedStore = 'selected_store_name';
  static const String _prefProfileCompleted = 'profile_completed';
  static const String _prefDriverName = 'driver_name';
  static const String _prefKycCompleted = 'kyc_completed';
  static const String _prefVehicleName = 'vehicle_name';
  static const String _prefVehicleLicensePlate = 'vehicle_license_plate';
  static const String _prefBankDocName = 'bank_doc_name';
  static const String _prefBankAccountName = 'bank_account_name';
  static const int _profileImageMaxBytes = 5 * 1024 * 1024;
  static const int _profileImageMinDimension = 200;
  static const int _profileImageMaxDimension = 4096;
  static const double _profileImageMinAspectRatio = 0.5;
  static const double _profileImageMaxAspectRatio = 2.0;
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
  String? _sessionToken;
  String _tokenType = 'Bearer';
  String? _configVersion;
  String? _driverName;

  DateTime? _lastOtpRequestAt;

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
  bool _isTracking = false;
  int _trackingInterval = 10;
  String _liveCoordinates = '28.6139, 77.2090';
  double? _currentLatitude;
  double? _currentLongitude;
  String? _currentLocationLabel;
  String? _selectedStoreName;
  String? _profileImagePath;

  DeliveryOrder? _incomingOrder;
  DeliveryOrder? _activeOrder;

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
  String? get sessionToken => _sessionToken;
  bool get rememberMe => _rememberMe;
  bool get profileCompleted => _profileCompleted;
  bool get kycCompleted => _kycCompleted;
  String get languageCode => _languageCode;
  String? get configVersion => _configVersion;
  PartnerProfile? get profile => _profile;
  LoggedPartnerProfileDetails? get loggedProfileDetails =>
      _loggedProfileDetails;
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
  bool get isTracking => _isTracking;
  int get trackingInterval => _trackingInterval;
  String get liveCoordinates => _liveCoordinates;
  double? get currentLatitude => _currentLatitude;
  double? get currentLongitude => _currentLongitude;
  String? get currentLocationLabel => _currentLocationLabel;
  String? get selectedStoreName => _selectedStoreName;
  String? get profileImagePath => _profileImagePath;
  bool get hasSelectedLocation =>
      _currentLatitude != null && _currentLongitude != null;
  DeliveryOrder? get incomingOrder => _incomingOrder;
  DeliveryOrder? get activeOrder => _activeOrder;
  EarningsSummary get earnings => _earnings;
  PerformanceMetrics get performance => _performance;
  List<AppNotice> get notices => List<AppNotice>.unmodifiable(_notices);

  String? get driverName => _driverName;
  String? get registrationToken => _registrationToken;
  String? get pendingRegistrationMobile => _pendingRegistrationMobile;

  bool get allKycApproved => _kycStatus.values.every(
    (status) => status == VerificationStatus.approved,
  );

  bool get isKycComplete => _kycCompleted;

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
    _tokenType = _nullIfBlank(prefs.getString(_prefTokenType)) ?? 'Bearer';
    _rememberMe = prefs.getBool(_prefRememberMe) ?? false;
    _profileCompleted = prefs.getBool(_prefProfileCompleted) ?? false;
    _kycCompleted = prefs.getBool(_prefKycCompleted) ?? false;
    _currentLatitude = prefs.getDouble(_prefCurrentLat);
    _currentLongitude = prefs.getDouble(_prefCurrentLng);
    _currentLocationLabel = _nullIfBlank(
      prefs.getString(_prefCurrentLocationLabel),
    );
    _selectedStoreName = _nullIfBlank(prefs.getString(_prefSelectedStore));
    _driverName = _nullIfBlank(prefs.getString(_prefDriverName));
    _profileImagePath = _nullIfBlank(prefs.getString(_prefProfileImagePath));
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
    final String? imageValidationError = await _validateProfileImage(
      sourcePath,
    );
    if (imageValidationError != null) {
      return imageValidationError;
    }

    _profileImageSyncing = true;
    _profileImageSyncError = null;
    notifyListeners();

    try {
      final String localPath = await _copyProfileImageToAppStorage(sourcePath);
      await setProfileImagePath(localPath);

      if (_loggedProfileDetails?.driver == null) {
        await fetchLoggedInEmployeeDriverProfile(forceRefresh: true);
      }
      final String? employeeName = _nullIfBlank(
        _loggedProfileDetails?.driver?['employee']?.toString(),
      );
      if (employeeName == null) {
        _profileImageSyncError =
            'Image saved on this device. Employee link missing for web sync.';
        return _profileImageSyncError;
      }

      final Uri uploadUri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/method/upload_file',
      );
      final Map<String, dynamic> uploadPayload = await _authorizedUploadFile(
        uri: uploadUri,
        filePath: localPath,
        fields: <String, String>{
          'is_private': '0',
          'doctype': 'Employee',
          'docname': employeeName,
          'fieldname': 'image',
        },
      );

      final String? fileUrl = _extractUploadedFileUrl(uploadPayload);
      if (fileUrl == null) {
        throw Exception(
          'Image uploaded but file URL missing in server response',
        );
      }

      final Uri employeeUri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/resource/Employee/${Uri.encodeComponent(employeeName)}',
      );
      await _authorizedPutJson(employeeUri, <String, dynamic>{
        'image': fileUrl,
      });
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

  Future<String?> _validateProfileImage(String sourcePath) async {
    final String ext = _fileExtension(sourcePath).toLowerCase();
    if (!_profileImageAllowedExtensions.contains(ext)) {
      return 'Only JPG or PNG images are allowed.';
    }

    final File file = File(sourcePath);
    final int bytes = await file.length();
    if (bytes <= 0) {
      return 'Selected image is empty. Pick another image.';
    }
    if (bytes > _profileImageMaxBytes) {
      return 'Image size must be 5 MB or less.';
    }

    final Size? size = await _readImageSize(file);
    if (size == null) {
      return 'Unable to read image dimensions. Pick another image.';
    }

    if (size.width < _profileImageMinDimension ||
        size.height < _profileImageMinDimension) {
      return 'Image dimensions must be at least 200 x 200 px.';
    }
    if (size.width > _profileImageMaxDimension ||
        size.height > _profileImageMaxDimension) {
      return 'Image dimensions must be below 4096 x 4096 px.';
    }

    final double ratio = size.width / size.height;
    if (ratio < _profileImageMinAspectRatio ||
        ratio > _profileImageMaxAspectRatio) {
      return 'Image aspect ratio must be between 1:2 and 2:1.';
    }

    return null;
  }

  Future<Size?> _readImageSize(File file) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(
        await file.readAsBytes(),
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image image = frame.image;
      final Size size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return null;
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
      _logApi('http', 'POST $_sendOtpUri');
      final http.Response response = await http
          .post(
            _sendOtpUri,
            headers: const <String, String>{'Accept': 'application/json'},
            body: <String, String>{
              'mobile_no': mobile.trim(),
              'store_id': _storeId,
            },
          )
          .timeout(_networkTimeout);
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
      _logApi(
        'verify_whatsapp_otp request',
        <String, String>{
          'mobile_no': mobile.trim(),
          'otp': otp.trim(),
          'store_id': _storeId,
        }.toString(),
      );
      _logApi('http', 'POST $_verifyOtpUri');
      final http.Response response = await http
          .post(
            _verifyOtpUri,
            headers: const <String, String>{'Accept': 'application/json'},
            body: <String, String>{
              'mobile_no': mobile.trim(),
              'otp': otp.trim(),
              'store_id': _storeId,
            },
          )
          .timeout(_networkTimeout);
      _logApi(
        'verify_whatsapp_otp response',
        'status=${response.statusCode} body=${response.body}',
      );

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
      notifyListeners();
      return null;
    } catch (e) {
      _logApi('verify_whatsapp_otp error', e.toString());
      if (e is TimeoutException) {
        return 'Request timed out. Please try again.';
      }
      return 'Unable to connect. Check internet and try again.';
    }
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

      _logApi('register_delivery_partner request', body.toString());
      final http.Response response = await http.post(
        _registerPartnerUri,
        headers: const <String, String>{'Accept': 'application/json'},
        body: body,
      );
      _logApi(
        'register_delivery_partner response',
        'status=${response.statusCode} body=${response.body}',
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
      notifyListeners();
      return null;
    } catch (e) {
      _logApi('register_delivery_partner error', e.toString());
      return 'Unable to connect. Check internet and try again.';
    }
  }

  Future<void> logout() async {
    _isLoggedIn = false;
    _sessionToken = null;
    _tokenType = 'Bearer';
    _isOnline = false;
    _isTracking = false;
    _incomingOrder = null;
    _activeOrder = null;
    _profile = null;
    _loggedProfileDetails = null;
    _profileDetailsError = null;
    _profileDetailsLoading = false;
    _profileCompleted = false;
    _kycCompleted = false;
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
      prefs.remove(_prefKycCompleted),
      prefs.remove(_prefDriverName),
      prefs.remove(_prefVehicleName),
      prefs.remove(_prefVehicleLicensePlate),
      prefs.remove(_prefBankDocName),
      prefs.remove(_prefBankAccountName),
      prefs.setBool(_prefRememberMe, false),
    ]);
    _rememberMe = false;
    notifyListeners();
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
      _logApi('upload_kyc_file', 'SKIP: no session token');
      return null;
    }
    try {
      _logApi(
        'upload_kyc_file request',
        'driver_name=$docname fieldname=$fieldname file=$fileName',
      );
      final http.MultipartRequest request = http.MultipartRequest(
        'POST',
        _uploadFileUri,
      );
      request.headers['Authorization'] = 'Bearer $_sessionToken';
      request.files.add(
        await http.MultipartFile.fromPath('file', filePath, filename: fileName),
      );
      if (docname != null && docname.isNotEmpty) {
        request.fields['driver_name'] = docname;
      }
      if (fieldname != null && fieldname.isNotEmpty) {
        request.fields['fieldname'] = fieldname;
      }

      final http.StreamedResponse streamed = await request.send();
      final String body = await streamed.stream.bytesToString();
      _logApi(
        'upload_kyc_file response',
        'status=${streamed.statusCode} body=$body',
      );

      final Map<String, dynamic> payload = _decodeJsonMap(body);

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final String? serverError = _extractServerError(payload);
        _logApi(
          'upload_kyc_file FAIL',
          serverError ?? 'HTTP ${streamed.statusCode}',
        );
        return null;
      }

      final Map<String, dynamic> data = _extractMethodData(payload);
      return _nullIfBlank(data['file_url']?.toString());
    } catch (e) {
      _logApi('upload_kyc_file error', e.toString());
      return null;
    }
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

      _logApi('submit_driver_kyc request', body.toString());
      final http.Response response = await http.post(
        _submitDriverKycUri,
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $_sessionToken',
        },
        body: body,
      );
      _logApi(
        'submit_driver_kyc response',
        'status=${response.statusCode} body=${response.body}',
      );

      final Map<String, dynamic> payload = _decodeJsonMap(response.body);
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
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_prefKycCompleted, true);
        notifyListeners();
        return null;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _extractServerError(payload) ??
            'KYC submission failed (${response.statusCode})';
      }
      return _extractServerError(payload) ?? 'KYC submission failed';
    } catch (e) {
      _logApi('submit_driver_kyc error', e.toString());
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
      final String? vehicleName = _nullIfBlank(prefs.getString(_prefVehicleName));
      final String? licensePlate = _nullIfBlank(
        prefs.getString(_prefVehicleLicensePlate),
      );

      Map<String, dynamic>? data;
      if (vehicleName != null) {
        data = await fetchVehicleByName(vehicleName);
      }
      data ??= await fetchVehicleByLicensePlate(licensePlate ?? '');
      if (data == null) {
        return;
      }

      _submittedVehicleRaw = data;
      _vehicle = _vehicleFromApiData(data);
      notifyListeners();
    } catch (_) {
      // Ignore hydration failures; screen stays editable.
    }
  }

  Future<List<String>> fetchVehicleEmployeeOptions({String query = ''}) async {
    try {
      final Uri uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/method/frappe.desk.search.search_link',
      );
      final Map<String, String> body = <String, String>{
        'doctype': 'Employee',
        'ignore_user_permissions': '0',
        'reference_doctype': 'Vehicle',
        'page_length': '10',
        'start': '0',
        'txt': query.trim(),
      };
      final Map<String, dynamic> payload = await _authorizedPostForm(
        uri: uri,
        body: body,
      );
      final dynamic responseRows =
          payload['message'] ?? payload['results'] ?? payload['data'];
      if (responseRows is! List) {
        return <String>[];
      }

      final List<String> values = <String>[];
      for (final dynamic item in responseRows) {
        if (item is Map<String, dynamic>) {
          final String? value =
              _nullIfBlank(item['value']?.toString()) ??
              _nullIfBlank(item['name']?.toString()) ??
              _nullIfBlank(item['description']?.toString());
          if (value != null && !values.contains(value)) {
            values.add(value);
          }
        } else if (item is List && item.isNotEmpty) {
          final String? value = _nullIfBlank(item.first?.toString());
          if (value != null && !values.contains(value)) {
            values.add(value);
          }
        } else if (item != null) {
          final String? value = _nullIfBlank(item.toString());
          if (value != null && !values.contains(value)) {
            values.add(value);
          }
        }
      }
      return values;
    } catch (_) {
      return <String>[];
    }
  }

  Future<List<String>> fetchLinkOptions({
    required String doctype,
    String referenceDoctype = 'Bank Account',
    String query = '',
    int pageLength = 10,
    Map<String, dynamic>? filters,
  }) async {
    try {
      final Uri uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/method/frappe.desk.search.search_link',
      );
      final Map<String, String> body = <String, String>{
        'doctype': doctype,
        'ignore_user_permissions': '0',
        'reference_doctype': referenceDoctype,
        'page_length': '$pageLength',
        'start': '0',
        'txt': query.trim(),
      };
      if (filters != null && filters.isNotEmpty) {
        body['filters'] = jsonEncode(filters);
      }
      final Map<String, dynamic> payload = await _authorizedPostForm(
        uri: uri,
        body: body,
      );
      final dynamic responseRows =
          payload['message'] ?? payload['results'] ?? payload['data'];
      if (responseRows is! List) {
        return <String>[];
      }

      final List<String> values = <String>[];
      for (final dynamic item in responseRows) {
        if (item is Map<String, dynamic>) {
          final String? value =
              _nullIfBlank(item['value']?.toString()) ??
              _nullIfBlank(item['name']?.toString());
          if (value != null && !values.contains(value)) {
            values.add(value);
          }
        } else if (item is List && item.isNotEmpty) {
          final String? value = _nullIfBlank(item.first?.toString());
          if (value != null && !values.contains(value)) {
            values.add(value);
          }
        } else if (item != null) {
          final String? value = _nullIfBlank(item.toString());
          if (value != null && !values.contains(value)) {
            values.add(value);
          }
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
      final String? bankDocName = _nullIfBlank(prefs.getString(_prefBankDocName));
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
      if (data == null) {
        return;
      }

      _submittedBankRaw = data;
      _bank = _bankFromApiData(data);
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
        responsePayload = await _authorizedPutJson(updateUri, body);
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
    String? account,
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
    String? bankAccountNo,
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

    final String? normalizedAccount = _nullIfBlank(account);
    final String? normalizedAccountType = _nullIfBlank(accountType);
    final String? normalizedAccountSubtype = _nullIfBlank(accountSubtype);
    final String? normalizedCompany = _nullIfBlank(company);
    final String? normalizedPartyType = _nullIfBlank(partyType);
    final String? normalizedParty = _nullIfBlank(party);
    final String? normalizedBranchCode = _nullIfBlank(branchCode);
    final String? normalizedBankAccountNo = _nullIfBlank(bankAccountNo);
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
      r'^[A-Z0-9-]{2,20}$',
    ).hasMatch(normalizedBranchCode.toUpperCase())) {
      return 'Branch code should be 2-20 characters (A-Z, 0-9, -)';
    }
    if (normalizedBankAccountNo != null &&
        !RegExp(
          r'^[A-Z0-9-]{6,34}$',
        ).hasMatch(normalizedBankAccountNo.toUpperCase())) {
      return 'Bank account no should be 6-34 characters (A-Z, 0-9, -)';
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
      'disabled': disabled ? 1 : 0,
      'is_default': isDefault ? 1 : 0,
      'is_company_account': isCompanyAccount ? 1 : 0,
    };
    if (normalizedAccount != null) {
      body['account'] = normalizedAccount;
    }
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
    if (normalizedBankAccountNo != null) {
      body['bank_account_no'] = normalizedBankAccountNo.toUpperCase();
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
        responsePayload = await _authorizedPutJson(updateUri, body);
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
      await _persistBankIdentity(
        bankDocName:
            _nullIfBlank(_submittedBankRaw?['name']?.toString()) ?? bankName,
        accountName: normalizedAccountName,
      );
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
    _incomingOrder = DeliveryOrder(
      id: '#OD${1000 + _random.nextInt(8999)}',
      customerName: 'Riya Sharma',
      storeName: 'Fresh Bites Kitchen',
      contactNumber: '9876501234',
      pickup: 'Connaught Place, New Delhi',
      drop: 'Karol Bagh, New Delhi',
      deliveryInstructions: 'Call before arrival, gate code 2456',
      paymentMode: _random.nextBool() ? 'COD' : 'Online',
      distanceKm: 6.4,
      estimatedEarnings: 132,
      status: OrderProgressStatus.accepted,
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

    _activeOrder = _activeOrder!.copyWith(status: status);

    if (status == OrderProgressStatus.delivered) {
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
          message: 'Order ${_activeOrder!.id} delivered successfully.',
          time: DateTime.now(),
        ),
      );
      _activeOrder = null;
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
    final String? driverName = _nullIfBlank(message['driver_name']?.toString());
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
    if (backendProfileCompleted) {
      _profileCompleted = true;
    }
    _kycCompleted = backendKycCompleted;
    _tokenType = tokenType ?? _tokenType;

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

  void _writePref(Future<bool> Function(SharedPreferences prefs) writer) {
    unawaited(() async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await writer(prefs);
    }());
  }

  void _logApi(String tag, String value) {
    final String line = '[API] $tag => $value';
    // Keep debugPrint for Flutter tooling and print for plain logcat visibility.
    debugPrint(line);
    // ignore: avoid_print
    print(line);
  }

  void _updateLiveCoordinates() {
    final double baseLat = 28.6139;
    final double baseLng = 77.2090;
    final double lat = baseLat + (_random.nextDouble() - 0.5) / 100;
    final double lng = baseLng + (_random.nextDouble() - 0.5) / 100;
    _liveCoordinates = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  Future<void> fetchLoggedInEmployeeDriverProfile({
    bool forceRefresh = false,
  }) async {
    if (_profileDetailsLoading) {
      return;
    }
    if (!forceRefresh && _loggedProfileDetails?.hasData == true) {
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
      final String? loggedUser = await _fetchLoggedUser();
      String? driverName;
      Map<String, dynamic>? driverDoc;

      // Login identity is best mapped through mobile returned in OTP login flow.
      driverName = await _findDriverByMobile();

      // Secondary mapping only if login user is available and not generic admin.
      if (driverName == null &&
          loggedUser != null &&
          loggedUser.toLowerCase() != 'administrator') {
        final String? employeeName = await _findResourceName(
          doctype: 'Employee',
          filters: <List<String>>[
            <String>['Employee', 'user_id', '=', loggedUser],
          ],
          fields: <String>['name'],
        );
        if (employeeName != null) {
          driverName = await _findResourceName(
            doctype: 'Driver',
            filters: <List<String>>[
              <String>['Driver', 'employee', '=', employeeName],
            ],
            fields: <String>['name'],
          );
        }
      }
      driverName ??= await _findDefaultDriverName();

      if (driverName != null) {
        driverDoc = await _fetchResourceDoc('Driver', driverName);
      }

      _loggedProfileDetails = LoggedPartnerProfileDetails(
        loggedUser: loggedUser,
        employee: null,
        driver: driverDoc,
      );

      if (!(_loggedProfileDetails?.hasData ?? false)) {
        _profileDetailsError = 'No driver profile linked to this login account';
      }
    } catch (e) {
      _profileDetailsError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _profileDetailsLoading = false;
      notifyListeners();
    }
  }

  Future<String?> _fetchLoggedUser() async {
    final Uri uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.auth.get_logged_user',
    );
    final Map<String, dynamic> payload = await _authorizedGet(uri);
    return _nullIfBlank(payload['message']?.toString());
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

  Future<String?> _findDefaultDriverName() async {
    final String configured = ApiConstants.defaultExternalDeliveryDriver.trim();
    if (configured.isNotEmpty) {
      final Map<String, dynamic>? configuredDoc = await _fetchResourceDoc(
        'Driver',
        configured,
      );
      if (configuredDoc != null) {
        return configured;
      }
    }

    return _findResourceName(
      doctype: 'Driver',
      filters: const <List<String>>[],
      fields: const <String>['name'],
    );
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
      _logApi('http', 'GET $uri');
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
    throw Exception(lastError ?? 'Authentication failed for GET $uri');
  }

  Future<Map<String, dynamic>> _authorizedPutJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final List<Map<String, String>> authHeaders = _authorizationHeaders(
      contentType: 'application/json',
    );

    String? lastError;
    for (final Map<String, String> headers in authHeaders) {
      _logApi('http', 'PUT $uri');
      final http.Response response = await http
          .put(uri, headers: headers, body: jsonEncode(body))
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
    throw Exception(lastError ?? 'Authentication failed for PUT $uri');
  }

  Future<Map<String, dynamic>> _authorizedPostJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final List<Map<String, String>> authHeaders = _authorizationHeaders(
      contentType: 'application/json',
    );

    String? lastError;
    for (final Map<String, String> headers in authHeaders) {
      _logApi('http', 'POST $uri');
      final http.Response response = await http
          .post(uri, headers: headers, body: jsonEncode(body))
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
    throw Exception(lastError ?? 'Authentication failed for POST $uri');
  }

  Future<Map<String, dynamic>> _authorizedPostForm({
    required Uri uri,
    required Map<String, String> body,
  }) async {
    final List<Map<String, String>> authHeaders = _authorizationHeaders();
    String? lastError;
    for (final Map<String, String> headers in authHeaders) {
      _logApi('http', 'POST $uri');
      final http.Response response = await http
          .post(uri, headers: headers, body: body)
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
    throw Exception(lastError ?? 'Authentication failed for POST $uri');
  }

  Future<Map<String, dynamic>> _authorizedUploadFile({
    required Uri uri,
    required String filePath,
    required Map<String, String> fields,
  }) async {
    final List<Map<String, String>> authHeaders = _authorizationHeaders();

    String? lastError;
    for (final Map<String, String> headers in authHeaders) {
      _logApi('http', 'POST $uri');
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
    throw Exception(lastError ?? 'Authentication failed for POST $uri');
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

  List<Map<String, String>> _authorizationHeaders({String? contentType}) {
    final List<Map<String, String>> authHeaders = <Map<String, String>>[];
    if (_sessionToken != null && _sessionToken!.trim().isNotEmpty) {
      final Map<String, String> bearerHeaders = <String, String>{
        'Accept': 'application/json',
        'Authorization': '${_tokenType.trim()} ${_sessionToken!.trim()}',
      };
      if (contentType != null) {
        bearerHeaders['Content-Type'] = contentType;
      }
      authHeaders.add(bearerHeaders);
    }
    final Map<String, String> tokenHeaders = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'token ${ApiConstants.apiKey}:${ApiConstants.apiSecret}',
    };
    if (contentType != null) {
      tokenHeaders['Content-Type'] = contentType;
    }
    authHeaders.add(tokenHeaders);
    return authHeaders;
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
