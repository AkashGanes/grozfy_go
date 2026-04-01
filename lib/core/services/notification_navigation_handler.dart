import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../main.dart';
import '../navigation/app_routes.dart';

class NotificationNavigationHandler {
  static final NotificationNavigationHandler _instance =
      NotificationNavigationHandler._internal();
  factory NotificationNavigationHandler() => _instance;
  NotificationNavigationHandler._internal();

  void handleMessage(RemoteMessage message) {
    final String? doctype =
        (message.data['doctype'] ?? message.data['type'] ?? '').toString();
    final String? docname =
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

  void _navigateToTarget(String? doctype, String? docname) {
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
