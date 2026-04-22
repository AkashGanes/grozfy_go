import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
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
        debugPrint('FCM subscribe skipped: token is null');
        return;
      }

      final String projectId = Firebase.apps.isNotEmpty
          ? Firebase.app().options.projectId
          : '';
      if (projectId.isEmpty) {
        debugPrint('FCM Subscription error: Firebase project id missing');
        return;
      }

      debugPrint(
        'FCM subscribe attempt: '
        'endpoint=${ApiConstants.erpBaseUrl}/api/method/frappe.push_notification.subscribe, '
        'projectId=$projectId, tokenPrefix=${_maskToken(token)}',
      );

      final bool registered = await _registerDeviceWithErpNext(
        baseUrl: ApiConstants.erpBaseUrl,
        fcmToken: token,
        projectName: projectId,
        bearerToken: appController.sessionToken,
      );
      if (!registered) {
        debugPrint('FCM subscribe failed');
        return;
      }

      _bindTokenRefresh(appController);
      debugPrint("FCM token sync successful");
    } catch (e) {
      debugPrint("FCM Subscription error: $e");
    }
  }

  Future<void> unsubscribe(AppController appController) async {
    if (!appController.isLoggedIn || appController.sessionToken == null) return;

    try {
      final String? token = await getToken();
      if (token == null) {
        debugPrint('FCM unsubscribe skipped: token is null');
        return;
      }

      final String projectId = Firebase.apps.isNotEmpty
          ? Firebase.app().options.projectId
          : '';
      if (projectId.isEmpty) {
        debugPrint('FCM Unsubscription error: Firebase project id missing');
        return;
      }

      debugPrint(
        'FCM unsubscribe attempt: '
        'endpoint=${ApiConstants.erpBaseUrl}/api/method/frappe.push_notification.unsubscribe, '
        'projectId=$projectId, tokenPrefix=${_maskToken(token)}',
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
        debugPrint("FCM Unsubscription successful");
      } else {
        debugPrint("FCM unsubscribe failed");
      }
    } catch (e) {
      debugPrint("FCM Unsubscription error: $e");
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
      debugPrint(
        "FCM unsubscribe (explicit token): ${unsubscribed ? 'success' : 'failed'}",
      );
    } catch (e) {
      debugPrint("FCM unsubscribe (explicit token) error: $e");
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
          debugPrint('FCM token refresh sync error: Firebase project id missing');
          return;
        }

        debugPrint(
          'FCM token refresh attempt: '
          'projectId=$projectId, tokenPrefix=${_maskToken(token)}',
        );

        await _registerDeviceWithErpNext(
          baseUrl: ApiConstants.erpBaseUrl,
          fcmToken: token,
          projectName: projectId,
          bearerToken: appController.sessionToken,
        );
        debugPrint("FCM token refresh synced");
      } catch (e) {
        debugPrint("FCM token refresh sync error: $e");
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
        debugPrint('FCM device registered with ERPNext: ${response.body}');
        return true;
      }

      debugPrint(
        'FCM registration failed: status=${response.statusCode}, body=${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('FCM registration error: $e');
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
        debugPrint('FCM device unsubscribed from ERPNext: ${response.body}');
        return true;
      }

      debugPrint(
        'FCM unsubscription failed: status=${response.statusCode}, body=${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('FCM unsubscription error: $e');
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
