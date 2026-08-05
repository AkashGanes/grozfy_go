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

/// Launches a single Google Maps session covering every stop in [stops] (in
/// the given order) as one multi-stop driving route — the last entry becomes
/// the route's `destination`, everything before it becomes `waypoints`.
/// Google Maps then handles stop-to-stop progression natively as the driver
/// arrives at each waypoint, so the app only needs to call this once per
/// distinct route (typically: once on trip open, and again whenever the set
/// of remaining stops changes after a completion) instead of relaunching to
/// a single destination per stop.
///
/// Unlike [launchGoogleMapsNavigation], this always goes through the web
/// "dir" URL (`google.com/maps/dir/...`) rather than platform-specific
/// intent schemes: the native `google.navigation:`/`comgooglemaps://`
/// schemes are single-destination only and don't support `waypoints`. The
/// web URL is intercepted by the installed Google Maps app on both Android
/// and iOS (via app-link association) when available, and otherwise opens
/// in a browser — the same universal-fallback behavior
/// [launchGoogleMapsNavigation] already relies on for its own web fallback.
Future<void> launchGoogleMapsMultiStopNavigation(
  BuildContext context, {
  required List<(double, double)> stops,
}) async {
  if (stops.isEmpty) return;

  final (double, double) destination = stops.last;
  final List<(double, double)> waypointStops = stops.length > 1
      ? stops.sublist(0, stops.length - 1)
      : const [];

  final Uri uri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1'
    '&destination=${destination.$1},${destination.$2}'
    '${waypointStops.isEmpty ? '' : '&waypoints=${waypointStops.map((c) => '${c.$1},${c.$2}').join('|')}'}'
    '&travelmode=driving',
  );
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}

  if (context.mounted) {
    AppToast.show(context, 'Could not open maps');
  }
}
