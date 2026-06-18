import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../logging/app_logger.dart';
import '../state/app_controller.dart';

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  StreamSubscription<String>? _tokenRefreshSub;

  Future<String?> getToken() async {
    return await _fcm.getToken();
  }

  Future<void> subscribe(AppController appController) async {
    if (!appController.isLoggedIn || appController.sessionToken == null) return;

    try {
      final String? token = await getToken();
      if (token == null) {
        AppLogger.fcm.warning('Subscribe skipped: token is null');
        return;
      }

      final String projectId = Firebase.apps.isNotEmpty
          ? Firebase.app().options.projectId
          : '';
      if (projectId.isEmpty) {
        AppLogger.fcm.error('Subscription error: Firebase project id missing');
        return;
      }

      AppLogger.fcm.debug(
        'Subscribe attempt',
        data: {
          'endpoint':
              '${ApiConstants.erpBaseUrl}/api/method/frappe.push_notification.subscribe',
          'projectId': projectId,
          'tokenPrefix': _maskToken(token),
        },
      );

      final bool registered = await _registerDeviceWithErpNext(
        baseUrl: ApiConstants.erpBaseUrl,
        fcmToken: token,
        projectName: projectId,
        bearerToken: appController.sessionToken,
      );
      if (!registered) {
        AppLogger.fcm.warning('Subscribe failed');
        return;
      }

      _bindTokenRefresh(appController);
      AppLogger.fcm.info('Token sync successful');
    } catch (e) {
      AppLogger.fcm.error('Subscription error', error: e);
    }
  }

  Future<void> unsubscribe(AppController appController) async {
    if (!appController.isLoggedIn || appController.sessionToken == null) return;

    try {
      final String? token = await getToken();
      if (token == null) {
        AppLogger.fcm.warning('Unsubscribe skipped: token is null');
        return;
      }

      final String projectId = Firebase.apps.isNotEmpty
          ? Firebase.app().options.projectId
          : '';
      if (projectId.isEmpty) {
        AppLogger.fcm.error('Unsubscription error: Firebase project id missing');
        return;
      }

      AppLogger.fcm.debug(
        'Unsubscribe attempt',
        data: {
          'endpoint':
              '${ApiConstants.erpBaseUrl}/api/method/frappe.push_notification.unsubscribe',
          'projectId': projectId,
          'tokenPrefix': _maskToken(token),
        },
      );

      final bool unsubscribed = await _unsubscribeDeviceFromErpNext(
        baseUrl: ApiConstants.erpBaseUrl,
        fcmToken: token,
        projectName: projectId,
        bearerToken: appController.sessionToken,
      );

      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
      if (unsubscribed) {
        AppLogger.fcm.info('Unsubscription successful');
      } else {
        AppLogger.fcm.warning('Unsubscribe failed');
      }
    } catch (e) {
      AppLogger.fcm.error('Unsubscription error', error: e);
    }
  }

  /// Fire-and-forget variant used during logout where the session token is
  /// about to be cleared from AppController. The caller snapshots the bearer
  /// token and passes it explicitly so this keeps working after logout.
  Future<void> unsubscribeWithToken({required String bearerToken}) async {
    try {
      final String? fcmToken = await getToken();
      if (fcmToken == null) return;

      final String projectId = Firebase.apps.isNotEmpty
          ? Firebase.app().options.projectId
          : '';
      if (projectId.isEmpty) return;

      final bool unsubscribed = await _unsubscribeDeviceFromErpNext(
        baseUrl: ApiConstants.erpBaseUrl,
        fcmToken: fcmToken,
        projectName: projectId,
        bearerToken: bearerToken,
      );

      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
      AppLogger.fcm.info(
        'Unsubscribe (explicit token): ${unsubscribed ? 'success' : 'failed'}',
      );
    } catch (e) {
      AppLogger.fcm.error('Unsubscribe (explicit token) error', error: e);
    }
  }

  void _bindTokenRefresh(AppController appController) {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _fcm.onTokenRefresh.listen((String token) async {
      try {
        final String projectId = Firebase.apps.isNotEmpty
            ? Firebase.app().options.projectId
            : '';
        if (projectId.isEmpty) {
          AppLogger.fcm.error('Token refresh sync error: Firebase project id missing');
          return;
        }

        AppLogger.fcm.debug(
          'Token refresh attempt',
          data: {'projectId': projectId, 'tokenPrefix': _maskToken(token)},
        );

        await _registerDeviceWithErpNext(
          baseUrl: ApiConstants.erpBaseUrl,
          fcmToken: token,
          projectName: projectId,
          bearerToken: appController.sessionToken,
        );
        AppLogger.fcm.info('Token refresh synced');
      } catch (e) {
        AppLogger.fcm.error('Token refresh sync error', error: e);
      }
    });
  }

  Future<bool> _registerDeviceWithErpNext({
    required String baseUrl,
    required String fcmToken,
    required String projectName,
    String? bearerToken,
  }) async {
    try {
      final Uri url = Uri.parse('$baseUrl/api/method/frappe.push_notification.subscribe');
      final Map<String, String> headers = <String, String>{};
      if (bearerToken != null && bearerToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $bearerToken';
      }

      final http.Response response = await http.get(
        url.replace(
          queryParameters: <String, String>{
            'fcm_token': fcmToken,
            'project_name': projectName,
          },
        ),
        headers: headers,
      );

      if (response.statusCode == 200) {
        AppLogger.fcm.info('Device registered with ERPNext');
        return true;
      }

      AppLogger.fcm.warning(
        'Registration failed',
        data: {'status': response.statusCode, 'body': response.body},
      );
      return false;
    } catch (e) {
      AppLogger.fcm.error('Registration error', error: e);
      return false;
    }
  }

  Future<bool> _unsubscribeDeviceFromErpNext({
    required String baseUrl,
    required String fcmToken,
    required String projectName,
    String? bearerToken,
  }) async {
    try {
      final Uri url = Uri.parse('$baseUrl/api/method/frappe.push_notification.unsubscribe');
      final Map<String, String> headers = <String, String>{};
      if (bearerToken != null && bearerToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $bearerToken';
      }

      final http.Response response = await http.get(
        url.replace(
          queryParameters: <String, String>{
            'fcm_token': fcmToken,
            'project_name': projectName,
          },
        ),
        headers: headers,
      );

      if (response.statusCode == 200) {
        AppLogger.fcm.info('Device unsubscribed from ERPNext');
        return true;
      }

      AppLogger.fcm.warning(
        'Unsubscription failed',
        data: {'status': response.statusCode, 'body': response.body},
      );
      return false;
    } catch (e) {
      AppLogger.fcm.error('Unsubscription error', error: e);
      return false;
    } finally {
      await _fcm.deleteToken();
    }
  }

  String _maskToken(String token) {
    if (token.length <= 10) return token;
    return '${token.substring(0, 5)}...${token.substring(token.length - 4)}';
  }
}
