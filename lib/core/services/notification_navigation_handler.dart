import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart';
import '../navigation/app_routes.dart';

class NotificationNavigationHandler {
  static final NotificationNavigationHandler _instance =
      NotificationNavigationHandler._internal();
  factory NotificationNavigationHandler() => _instance;
  NotificationNavigationHandler._internal();

  // FCM doctypes that represent an order/trip assignment. Tapping one of
  // these must not open an order screen while the driver is Offline — a
  // stale alert can linger in the tray after they go Offline.
  static const Set<String> _orderDoctypes = <String>{
    'External Delivery',
    'External Delivery Trip',
    'new_delivery',
    'new_trip',
  };

  // Same pref key that setOnline() persists and the foreground/background
  // message handlers gate on.
  static const String _prefIsOnline = 'is_online';

  void handleMessage(RemoteMessage message) {
    final String doctype =
        (message.data['doctype'] ?? message.data['type'] ?? '').toString();
    final String docname =
        (message.data['docname'] ?? message.data['doc_name'] ?? '').toString();

    debugPrint("Navigating from FCM Message - Type: $doctype, Name: $docname");
    _navigateToTarget(doctype, docname);
  }

  void handlePayload(String payload) {
    debugPrint("Navigating from Local Payload: $payload");
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        _navigateToTarget(
          decoded['doctype']?.toString(),
          decoded['docname']?.toString(),
        );
      }
    } catch (_) {
      // Ignore malformed payloads.
    }
  }

  Future<void> _navigateToTarget(String? doctype, String? docname) async {
    // Offline drivers must not be routed into an order/trip screen from a
    // notification still sitting in the tray. Non-order doctypes are left
    // alone so account/earnings alerts still open normally.
    if (doctype != null && _orderDoctypes.contains(doctype)) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefIsOnline) != true) {
        debugPrint(
          'Notification tap ignored: driver offline (doctype=$doctype)',
        );
        return;
      }
    }

    final normalizedDocname = docname?.trim();
    if ((doctype == 'External Delivery Trip' || doctype == 'new_trip') &&
        normalizedDocname != null &&
        normalizedDocname.isNotEmpty) {
      navigatorKey.currentState?.pushNamed(
        AppRoutes.externalDeliveryTripDetails,
        arguments: normalizedDocname,
      );
    } else if (doctype == 'External Delivery' ||
        doctype == 'new_delivery' ||
        doctype == 'External Delivery Trip' ||
        doctype == 'new_trip') {
      navigatorKey.currentState?.pushNamed(AppRoutes.notifications);
    }
  }
}
