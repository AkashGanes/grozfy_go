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
      final Size size = Size(
        image.width.toDouble(),
        image.height.toDouble(),
      );
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
        final String? newDriverName =
            _nullIfBlank(responseData['driver_name']?.toString());
        if (newDriverName != null) {
          _driverName = newDriverName;
          final SharedPreferences prefs =
              await SharedPreferences.getInstance();
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
}
