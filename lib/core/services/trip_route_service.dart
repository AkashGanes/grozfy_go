import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Best-effort real driving route via OSRM's free public routing service —
/// no API key, same OpenStreetMap data already used for address geocoding
/// elsewhere in this app. Returns null on any failure (timeout, network
/// error, malformed response, or no route found), so callers can fall back
/// to a straight-line connector instead.
class TripRouteService {
  TripRouteService._();

  static const String _baseUrl = 'https://router.project-osrm.org';

  /// Fetches a single driving route through `points`, in the given order
  /// (never reordered) — typically the driver's current position followed by
  /// the trip's pending stops in app-managed sequence. Returns the decoded
  /// road-following polyline, or null if unavailable.
  static Future<List<LatLng>?> fetchRoute(
    List<LatLng> points, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (points.length < 2) return null;
    try {
      final String coords = points
          .map((LatLng p) => '${p.longitude},${p.latitude}') // OSRM: lon,lat
          .join(';');
      final Uri uri = Uri.parse(
        '$_baseUrl/route/v1/driving/$coords'
        '?overview=full&geometries=geojson',
      );
      final http.Response response = await http
          .get(uri, headers: {'User-Agent': 'GrozfyGo/1.0'})
          .timeout(timeout);
      if (response.statusCode != 200) return null;

      final Map<String, dynamic> decoded =
          jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['code'] != 'Ok') return null;

      final List<dynamic>? routes = decoded['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;

      final Map<String, dynamic> geometry =
          (routes.first as Map<String, dynamic>)['geometry']
              as Map<String, dynamic>;
      final List<dynamic>? coordinates =
          geometry['coordinates'] as List<dynamic>?;
      if (coordinates == null || coordinates.length < 2) return null;

      return [
        for (final dynamic pair in coordinates)
          if (pair is List && pair.length >= 2)
            LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()),
      ];
    } catch (_) {
      return null;
    }
  }

  /// Same request/response as [fetchRoute], but also surfaces OSRM's
  /// `duration` field (seconds) for a best-effort ETA — kept as a separate
  /// method rather than changing [fetchRoute]'s signature, so its two
  /// existing callers are unaffected.
  static Future<({List<LatLng> points, double? durationSeconds})?>
  fetchRouteWithEta(
    List<LatLng> points, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (points.length < 2) return null;
    try {
      final String coords = points
          .map((LatLng p) => '${p.longitude},${p.latitude}')
          .join(';');
      final Uri uri = Uri.parse(
        '$_baseUrl/route/v1/driving/$coords'
        '?overview=full&geometries=geojson',
      );
      final http.Response response = await http
          .get(uri, headers: {'User-Agent': 'GrozfyGo/1.0'})
          .timeout(timeout);
      if (response.statusCode != 200) return null;

      final Map<String, dynamic> decoded =
          jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['code'] != 'Ok') return null;

      final List<dynamic>? routes = decoded['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;

      final Map<String, dynamic> route = routes.first as Map<String, dynamic>;
      final Map<String, dynamic> geometry =
          route['geometry'] as Map<String, dynamic>;
      final List<dynamic>? coordinates =
          geometry['coordinates'] as List<dynamic>?;
      if (coordinates == null || coordinates.length < 2) return null;

      final List<LatLng> decodedPoints = [
        for (final dynamic pair in coordinates)
          if (pair is List && pair.length >= 2)
            LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()),
      ];
      final double? durationSeconds = (route['duration'] as num?)?.toDouble();
      return (points: decodedPoints, durationSeconds: durationSeconds);
    } catch (_) {
      return null;
    }
  }
}
