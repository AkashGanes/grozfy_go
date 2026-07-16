import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/app_toast.dart';

/// Launches external navigation to [lat]/[lng] (preferred) or, when
/// coordinates aren't resolved yet, falls back to a Google Maps search for
/// [address]. At least one of (`lat` and `lng`) or `address` must be given.
Future<void> launchGoogleMapsNavigation(
  BuildContext context, {
  double? lat,
  double? lng,
  String? address,
}) async {
  if (lat != null && lng != null) {
    // Try each URI in order, launching without canLaunchUrl check because
    // custom schemes (google.navigation, comgooglemaps) can return false on
    // Android 11+ even when the app is installed.
    if (Platform.isAndroid) {
      // Native navigation intent — starts turn-by-turn from current GPS location.
      final Uri navUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
      try {
        if (await launchUrl(navUri, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {}

      // Fallback: geo URI with destination query (opens Maps or lets user choose).
      final Uri geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
      try {
        if (await launchUrl(geoUri, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {}
    }

    if (Platform.isIOS) {
      final Uri googleMapsIos = Uri.parse(
        'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving',
      );
      try {
        if (await launchUrl(googleMapsIos)) return;
      } catch (_) {}

      final Uri appleMaps = Uri.parse('maps:?daddr=$lat,$lng');
      try {
        if (await launchUrl(appleMaps)) return;
      } catch (_) {}
    }

    // Universal fallback: web Google Maps with driving directions.
    final Uri webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=$lat,$lng'
      '&travelmode=driving',
    );
    try {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return;
    } catch (_) {}
  } else if (address != null) {
    final Uri webUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=${Uri.encodeComponent(address)}',
    );
    try {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return;
    } catch (_) {}
  }

  if (context.mounted) {
    AppToast.show(context, 'Could not open maps');
  }
}
