import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../model/external_delivery.dart';
import '../model/external_delivery_detail.dart';
import '../repository/external_delivery_repository.dart';

class OrderLocationDetailScreen extends StatefulWidget {
  const OrderLocationDetailScreen({
    super.key,
    required this.order,
    required this.repository,
  });

  final ExternalDelivery order;
  final ExternalDeliveryRepository repository;

  @override
  State<OrderLocationDetailScreen> createState() =>
      _OrderLocationDetailScreenState();
}

class _OrderLocationDetailScreenState
    extends State<OrderLocationDetailScreen> {
  ExternalDeliveryDetail? _detail;
  bool _loading = true;
  String? _error;
  bool _updating = false;

  // Map & tracking state
  final MapController _mapController = MapController();
  bool _isMapReady = false;
  StreamSubscription<Position>? _positionStream;
  LatLng? _currentLocation;
  LatLng? _destination;
  double _currentHeading = 0;
  bool _isTracking = false;
  bool _hasArrived = false;
  bool _followMe = true;
  bool _arrivalDialogShown = false;
  double _distanceToDestination = 0;

  // Route state
  List<LatLng> _polylineCoordinates = [];
  bool _isFetchingRoute = false;
  DateTime? _lastRouteFetchAt;

  static const double _arrivalThreshold = 100.0;
  static const String _osrmBaseUrl =
      'https://router.project-osrm.org/route/v1/driving';
  static const Duration _routeRefreshInterval = Duration(seconds: 20);
  static const int _maxRoutePoints = 400;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Cancel stream FIRST so no more listener callbacks touch _mapController
    // or call setState after the widget is gone.
    _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
    _mapController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.fetchDetail(widget.order.name);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        if (detail.latitude != null && detail.longitude != null) {
          _destination = LatLng(detail.latitude!, detail.longitude!);
        }
      });
      await _initializeLocation();

      // If the order is already en route, resume live tracking automatically
      // so the driver immediately sees their position and distance on reopen.
      if (mounted &&
          detail.status.toLowerCase() == 'added to trip' &&
          _destination != null) {
        _startTracking();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Refresh only the detail data after a status update.
  /// Does NOT reset _loading (keeps map + tracking alive).
  Future<void> _refreshDetail() async {
    try {
      final detail = await widget.repository.fetchDetail(widget.order.name);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        if (detail.latitude != null && detail.longitude != null) {
          _destination = LatLng(detail.latitude!, detail.longitude!);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refresh failed: $e')),
        );
      }
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _updating = true);
    try {
      await widget.repository.updateStatus(widget.order.name, newStatus);
      await _refreshDetail();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Location & GPS
  // ---------------------------------------------------------------------------

  Future<void> _initializeLocation() async {
    final hasPermission = await _checkLocationPermission();
    if (!hasPermission || !mounted) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });

      if (_destination != null) {
        _getRoutePoints();
        _fitMapToPoints();
      } else if (_isMapReady) {
        try { _mapController.move(_currentLocation!, 16.0); } catch (_) {}
      }
    } catch (e) {
      debugPrint('Could not get GPS: $e');
    }
  }

  Future<bool> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  // ---------------------------------------------------------------------------
  // Live tracking
  // ---------------------------------------------------------------------------

  Future<void> _startTracking() async {
    if (_isTracking || _destination == null) return;

    final hasPermission = await _checkLocationPermission();
    if (!mounted) return;
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission is required to start tracking'),
        ),
      );
      return;
    }

    // Get a fresh position before starting the stream
    if (_currentLocation == null) {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
        if (!mounted) return;
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
      } catch (e) {
        debugPrint('Could not get initial GPS for tracking: $e');
        if (!mounted) return;
      }
    }

    if (!mounted) return;
    setState(() {
      _isTracking = true;
      _followMe = true;
    });

    if (_currentLocation != null && _polylineCoordinates.isEmpty) {
      _getRoutePoints();
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (Position position) {
        if (!mounted) return;

        final nextLocation = LatLng(position.latitude, position.longitude);
        final movedMeters = _currentLocation != null
            ? _calculateDistance(
                _currentLocation!.latitude, _currentLocation!.longitude,
                nextLocation.latitude, nextLocation.longitude)
            : 0.0;
        final nextHeading = movedMeters > 2 && _currentLocation != null
            ? _calculateBearing(_currentLocation!, nextLocation)
            : _currentHeading;

        setState(() {
          _currentLocation = nextLocation;
          _currentHeading = nextHeading;
          _updateRemainingRoute();
        });

        _checkArrival();

        if (_isMapReady && _isTracking && _followMe) {
          try {
            _mapController.move(_currentLocation!, 16.0);
          } catch (_) {}
        }

        if (_shouldRefreshRoute()) {
          _getRoutePoints();
        }
      },
      onError: (e) => debugPrint('Location stream error: $e'),
    );

    _fitMapToPoints();
  }

  void _stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // OSRM routing
  // ---------------------------------------------------------------------------

  Future<void> _getRoutePoints() async {
    if (_currentLocation == null || _destination == null || _isFetchingRoute) {
      return;
    }

    _isFetchingRoute = true;
    try {
      final routeData = await _fetchOsrmRoute(
        from: _currentLocation!,
        to: _destination!,
      );
      if (!mounted) return;

      if (routeData != null && routeData.points.length >= 2) {
        setState(() {
          _polylineCoordinates = routeData.points;
          _distanceToDestination = routeData.distanceMeters;
          _lastRouteFetchAt = DateTime.now();
          _updateRemainingRoute();
        });
      } else if (mounted) {
        _setFallbackRoute();
      }
    } catch (e) {
      debugPrint('Route fetch failed: $e');
      if (mounted) _setFallbackRoute();
    } finally {
      _isFetchingRoute = false;
    }

    if (mounted) _fitMapToPoints();
  }

  Future<_RouteData?> _fetchOsrmRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    // Build URL manually to avoid Uri.replace stripping the path
    final coords = '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
    final uri = Uri.parse(
      '$_osrmBaseUrl/$coords?overview=full&geometries=geojson&steps=false&alternatives=true',
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = payload['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return null;

    // Pick the shortest route if alternatives were returned
    Map<String, dynamic> bestRoute = routes.first as Map<String, dynamic>;
    double bestDistance = (bestRoute['distance'] as num?)?.toDouble() ?? double.infinity;
    for (int i = 1; i < routes.length; i++) {
      final r = routes[i] as Map<String, dynamic>;
      final d = (r['distance'] as num?)?.toDouble() ?? double.infinity;
      if (d < bestDistance) {
        bestRoute = r;
        bestDistance = d;
      }
    }

    final routeDistance = bestDistance;
    final geometry = bestRoute['geometry'] as Map<String, dynamic>?;
    final coordinates = geometry?['coordinates'] as List<dynamic>?;
    if (coordinates == null || coordinates.length < 2) return null;

    final routePoints = <LatLng>[
      for (final pair in coordinates)
        if (pair is List && pair.length >= 2 && pair[0] is num && pair[1] is num)
          LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()),
    ];

    if (routePoints.length < 2) return null;

    return _RouteData(
      points: _compressRoutePoints(routePoints),
      distanceMeters: routeDistance,
    );
  }

  List<LatLng> _compressRoutePoints(List<LatLng> points) {
    if (points.length <= _maxRoutePoints) return points;
    final stride = max(1, (points.length / _maxRoutePoints).ceil());
    final compressed = <LatLng>[];
    for (int i = 0; i < points.length; i += stride) {
      compressed.add(points[i]);
    }
    if (compressed.last != points.last) compressed.add(points.last);
    return compressed;
  }

  void _setFallbackRoute() {
    if (_currentLocation == null || _destination == null || !mounted) return;
    const numPoints = 30;
    final fallback = <LatLng>[];
    for (int i = 0; i <= numPoints; i++) {
      final lat = _currentLocation!.latitude +
          (_destination!.latitude - _currentLocation!.latitude) * i / numPoints;
      final lng = _currentLocation!.longitude +
          (_destination!.longitude - _currentLocation!.longitude) *
              i /
              numPoints;
      fallback.add(LatLng(lat, lng));
    }
    setState(() {
      _polylineCoordinates = fallback;
      _distanceToDestination = _calculateDistance(
        _currentLocation!.latitude, _currentLocation!.longitude,
        _destination!.latitude, _destination!.longitude,
      );
      _lastRouteFetchAt = DateTime.now();
    });
  }

  void _updateRemainingRoute() {
    if (_polylineCoordinates.length < 2 || _currentLocation == null) return;
    final nearestIdx = _findNearestRoutePointIndex(_currentLocation!);
    final nextIdx = min(nearestIdx + 1, _polylineCoordinates.length - 1);
    final remaining = <LatLng>[_currentLocation!, ..._polylineCoordinates.sublist(nextIdx)];
    if (_destination != null) {
      final last = remaining.last;
      final d = _calculateDistance(
        last.latitude, last.longitude,
        _destination!.latitude, _destination!.longitude,
      );
      if (d > 3) remaining.add(_destination!);
    }
    _polylineCoordinates = remaining;
  }

  int _findNearestRoutePointIndex(LatLng from) {
    int nearestIdx = 0;
    double nearestDist = double.infinity;
    for (int i = 0; i < _polylineCoordinates.length; i++) {
      final d = _calculateDistance(
        from.latitude, from.longitude,
        _polylineCoordinates[i].latitude, _polylineCoordinates[i].longitude,
      );
      if (d < nearestDist) {
        nearestDist = d;
        nearestIdx = i;
      }
    }
    return nearestIdx;
  }

  bool _shouldRefreshRoute() {
    if (_destination == null || _isFetchingRoute) return false;
    if (_lastRouteFetchAt == null) return true;
    return DateTime.now().difference(_lastRouteFetchAt!) >= _routeRefreshInterval;
  }

  // ---------------------------------------------------------------------------
  // Map helpers
  // ---------------------------------------------------------------------------

  void _fitMapToPoints() {
    if (!_isMapReady || !mounted) return;
    final points = <LatLng>[];
    if (_currentLocation != null) points.add(_currentLocation!);
    if (_destination != null) points.add(_destination!);
    if (points.length < 2) {
      if (points.length == 1) {
        try { _mapController.move(points.first, 16.0); } catch (_) {}
      }
      return;
    }
    try {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.fromLTRB(48, 80, 48, 300),
        ),
      );
    } catch (_) {}
  }

  void _checkArrival() {
    if (_destination == null || _currentLocation == null) return;
    final distance = _calculateDistance(
      _currentLocation!.latitude, _currentLocation!.longitude,
      _destination!.latitude, _destination!.longitude,
    );
    final wasArrived = _hasArrived;
    final nowArrived = distance < _arrivalThreshold;

    setState(() {
      _distanceToDestination = distance;
      _hasArrived = nowArrived;
    });

    // First time crossing the arrival threshold while actively delivering —
    // auto-show delivery confirmation dialog.
    if (!wasArrived &&
        nowArrived &&
        mounted &&
        !_arrivalDialogShown &&
        _isTracking &&
        _detail != null &&
        _detail!.status.toLowerCase() == 'added to trip') {
      _arrivalDialogShown = true;
      _showDeliveryConfirmationDialog();
    }
  }

  Future<void> _showDeliveryConfirmationDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        icon: const Icon(
          Icons.location_on_rounded,
          color: Color(0xFF2E7D32),
          size: 48,
        ),
        title: const Text(
          'You have arrived!',
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_formatDistance(_distanceToDestination)} from destination',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Have you handed over the order to the customer?',
              style: TextStyle(fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black54,
              side: const BorderSide(color: Colors.black26),
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Not Yet'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_circle_rounded, size: 20),
            label: const Text('Confirm Delivery'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirmed == true) {
      _onSlideDelivered();
    }
    // If "Not Yet" — dialog dismisses, driver continues tracking.
    // The slide button is still visible as a fallback to confirm later.
  }

  // ---------------------------------------------------------------------------
  // Math
  // ---------------------------------------------------------------------------

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRadians(double deg) => deg * pi / 180;

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = _toRadians(from.latitude);
    final lat2 = _toRadians(to.latitude);
    final dLon = _toRadians(to.longitude - from.longitude);
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  // ---------------------------------------------------------------------------
  // Status helpers
  // ---------------------------------------------------------------------------

  void _onSlideAcceptAndStart() {
    _updateStatus('Added to Trip');
    _startTracking();
  }

  Future<void> _onSlideDelivered() async {
    _stopTracking();
    setState(() => _updating = true);

    try {
      await widget.repository.updateStatus(widget.order.name, 'Delivered');
      await _refreshDetail();
    } catch (e) {
      if (mounted) {
        setState(() => _updating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mark delivered: $e')),
        );
      }
      return; // Don't show success dialog on failure
    }

    if (!mounted) return;
    setState(() => _updating = false);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        icon: const Icon(
          Icons.check_circle_rounded,
          color: Color(0xFF2E7D32),
          size: 52,
        ),
        title: const Text('Delivered!'),
        content: const Text(
          'Order has been delivered successfully.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _onCancelDelivery() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Color(0xFFE65100), size: 28),
            SizedBox(width: 10),
            Text('Cancel Delivery?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to cancel this delivery? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Delivery'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Delivery'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    _stopTracking();
    await _updateStatus('Failed');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Delivery cancelled'),
        backgroundColor: Color(0xFFC62828),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? _buildLoading()
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildLoading() {
    return Stack(
      children: [
        _buildMap(),
        const _BackButton(),
        DraggableScrollableSheet(
          initialChildSize: 0.28,
          minChildSize: 0.28,
          maxChildSize: 0.28,
          builder: (_, controller) => _SheetShell(
            scrollController: controller,
            child: const _LoadingSkeleton(),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Stack(
      children: [
        _buildMap(),
        const _BackButton(),
        DraggableScrollableSheet(
          initialChildSize: 0.35,
          minChildSize: 0.28,
          maxChildSize: 0.5,
          builder: (_, controller) => _SheetShell(
            scrollController: controller,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.redAccent, size: 36),
                const SizedBox(height: 8),
                Text(
                  _error ?? 'Something went wrong',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMap() {
    final initialCenter = _currentLocation ??
        _destination ??
        const LatLng(11.1271, 78.6569);

    return SafeMap(
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: initialCenter,
          initialZoom: 15.0,
          onMapReady: () {
            _isMapReady = true;
            if (!mounted) return;
            if (_currentLocation != null && _destination != null) {
              _fitMapToPoints();
            } else if (_currentLocation != null) {
              try { _mapController.move(_currentLocation!, 16.0); } catch (_) {}
            }
          },
          onPositionChanged: (camera, hasGesture) {
            if (hasGesture && _isTracking && _followMe) {
              setState(() => _followMe = false);
            }
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.delivery_partner_app',
          ),
          if (_polylineCoordinates.isNotEmpty)
            PolylineLayer(
              polylines: [
                // Route shadow for depth
                Polyline(
                  points: _polylineCoordinates,
                  color: AppTheme.oceanBlue.withValues(alpha: 0.3),
                  strokeWidth: 8.0,
                ),
                // Main route line
                Polyline(
                  points: _polylineCoordinates,
                  color: AppTheme.oceanBlue,
                  strokeWidth: 5.0,
                ),
              ],
            ),
          MarkerLayer(
            markers: [
              // Partner location marker (two-wheeler)
              if (_currentLocation != null)
                Marker(
                  point: _currentLocation!,
                  width: 56,
                  height: 56,
                  child: Transform.rotate(
                    angle: _toRadians(_currentHeading),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.oceanBlue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.oceanBlue.withValues(alpha: 0.4),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.two_wheeler,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              // Destination marker
              if (_destination != null)
                Marker(
                  point: _destination!,
                  width: 48,
                  height: 48,
                  child: const Icon(
                    Icons.location_pin,
                    color: Colors.redAccent,
                    size: 42,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final detail = _detail!;
    final statusColor = detail.status.statusColor;
    final s = detail.status.toLowerCase();

    return Stack(
      children: [
        _buildMap(),
        const _BackButton(),

        // Re-center button
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          right: 12,
          child: GestureDetector(
            onTap: () {
              if (_isMapReady && _currentLocation != null) {
                setState(() => _followMe = true);
                try { _mapController.move(_currentLocation!, 16.0); } catch (_) {}
              }
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _followMe && _isTracking
                    ? AppTheme.oceanBlue
                    : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.my_location_rounded,
                color: _followMe && _isTracking
                    ? Colors.white
                    : AppTheme.oceanBlue,
                size: 22,
              ),
            ),
          ),
        ),

        // Distance indicator (when tracking)
        if (_isTracking && _distanceToDestination > 0)
          Positioned(
            top: MediaQuery.of(context).padding.top + 56,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _hasArrived
                      ? const Color(0xFF2E7D32)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _hasArrived
                          ? Icons.check_circle_rounded
                          : Icons.two_wheeler,
                      size: 18,
                      color: _hasArrived ? Colors.white : AppTheme.oceanBlue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _hasArrived
                          ? 'Arrived · ${_formatDistance(_distanceToDestination)}'
                          : '${_formatDistance(_distanceToDestination)} away',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _hasArrived
                            ? Colors.white
                            : AppTheme.nightBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Bottom sheet
        DraggableScrollableSheet(
          initialChildSize: 0.42,
          minChildSize: 0.18,
          maxChildSize: 0.88,
          snap: true,
          snapSizes: const [0.18, 0.42, 0.88],
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 20,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(
                  20, 0, 20,
                  MediaQuery.of(context).padding.bottom + 16,
                ),
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Order ID + Store + Status
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              detail.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.nightBlue,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.store_rounded,
                                    size: 13, color: Colors.black38),
                                const SizedBox(width: 4),
                                Text(
                                  detail.storeName,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: statusColor.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          detail.status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 14),

                  // Customer
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppTheme.oceanBlue.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          color: AppTheme.oceanBlue,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              detail.customerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: AppTheme.nightBlue,
                              ),
                            ),
                            if (detail.contactMobile != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                detail.contactMobile!,
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.black45),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (detail.contactMobile != null)
                        _CallButton(mobile: detail.contactMobile!),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Addresses
                  _AddressRow(
                    icon: Icons.location_on_rounded,
                    iconColor: Colors.redAccent,
                    label: 'Delivery',
                    address:
                        detail.deliveryAddress ?? 'Address not available',
                  ),
                  if (detail.pickupAddress != null) ...[
                    const SizedBox(height: 12),
                    _AddressRow(
                      icon: Icons.store_rounded,
                      iconColor: AppTheme.oceanBlue,
                      label: 'Pickup',
                      address: detail.pickupAddress!,
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 14),

                  // Items
                  if (detail.items.isNotEmpty) ...[
                    const _SheetSectionLabel(
                        icon: Icons.shopping_bag_rounded, label: 'Items'),
                    const SizedBox(height: 10),
                    ...detail.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(right: 10, top: 1),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.oceanBlue,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                item.itemName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.nightBlue,
                                ),
                              ),
                            ),
                            Text(
                              'x${item.qty % 1 == 0 ? item.qty.toInt() : item.qty}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.nightBlue,
                              ),
                            ),
                            if (item.amount != null) ...[
                              const SizedBox(width: 14),
                              Text(
                                '₹${item.amount!.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.black45),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                  ],

                  // Action buttons based on ERPNext status:
                  // Pending → Added to Trip → Delivered / Failed
                  if (s != 'delivered' && s != 'failed' &&
                      s != 'returned' && s != 'return initiated') ...[
                    if (_updating)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.oceanBlue,
                            ),
                          ),
                        ),
                      ),

                    // Accept & start delivery (pending)
                    if (!_updating && (s == 'pending' || s == ''))
                      _SlideToAction(
                        key: const ValueKey('accept'),
                        label: 'Slide to Accept & Start Delivery',
                        color: const Color(0xFF4CAF50),
                        icon: Icons.local_shipping_rounded,
                        onSlideComplete: _onSlideAcceptAndStart,
                      ),

                    // Added to Trip — en route, waiting to reach destination
                    if (!_updating &&
                        s == 'added to trip' &&
                        !_hasArrived)
                      _InfoPill(
                        key: const ValueKey('enroute'),
                        icon: Icons.two_wheeler,
                        label: _distanceToDestination > 0
                            ? 'En route — ${_formatDistance(_distanceToDestination)} to destination'
                            : 'En route to destination',
                        color: const Color(0xFFFF9800),
                      ),

                    // Arrived near destination (within 100m) — confirm delivered
                    if (!_updating &&
                        s == 'added to trip' &&
                        _hasArrived)
                      _SlideToAction(
                        key: const ValueKey('delivered'),
                        label: 'Slide to Confirm Delivered',
                        color: const Color(0xFF4CAF50),
                        icon: Icons.done_all_rounded,
                        onSlideComplete: _onSlideDelivered,
                      ),

                    // Cancel delivery — available while en route
                    if (!_updating && s == 'added to trip')
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        child: OutlinedButton.icon(
                          onPressed: _onCancelDelivery,
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: const Text('Cancel Delivery'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFC62828),
                            side: const BorderSide(
                                color: Color(0xFFC62828), width: 1.2),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                  ],

                  if (s == 'delivered')
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'Delivered Successfully',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (s == 'failed')
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cancel_rounded,
                              color: Color(0xFFC62828), size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'Delivery Cancelled',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.red[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// =============================================================================
// Slide-to-action widget
// =============================================================================

class _SlideToAction extends StatefulWidget {
  const _SlideToAction({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
    required this.onSlideComplete,
  });

  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onSlideComplete;

  @override
  State<_SlideToAction> createState() => _SlideToActionState();
}

class _SlideToActionState extends State<_SlideToAction> {
  double _dragPosition = 0;
  bool _completed = false;
  bool _isDragging = false;

  static const double _thumbSize = 56;
  static const double _completeThreshold = 0.85;

  @override
  void didUpdateWidget(covariant _SlideToAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label || oldWidget.color != widget.color) {
      _completed = false;
      _dragPosition = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxDrag = constraints.maxWidth - _thumbSize;

          return SizedBox(
            height: 60,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Background track
                Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                        color: widget.color.withValues(alpha: 0.3)),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 40),
                      child: Text(
                        _completed ? 'Done!' : widget.label,
                        style: TextStyle(
                          color: widget.color,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                // Draggable thumb — uses its own GestureDetector so it wins
                // over the parent ListView's scroll recognizer.
                Positioned(
                  left: _dragPosition + 2,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) {
                      if (_completed) return;
                      _isDragging = true;
                    },
                    onHorizontalDragUpdate: (details) {
                      if (_completed || !_isDragging) return;
                      setState(() {
                        _dragPosition =
                            (_dragPosition + details.delta.dx)
                                .clamp(0.0, maxDrag);
                      });
                    },
                    onHorizontalDragEnd: (details) {
                      if (_completed || !_isDragging) return;
                      _isDragging = false;
                      if (_dragPosition / maxDrag >= _completeThreshold) {
                        setState(() => _completed = true);
                        widget.onSlideComplete();
                      } else {
                        setState(() => _dragPosition = 0);
                      }
                    },
                    onHorizontalDragCancel: () {
                      if (!_completed) {
                        _isDragging = false;
                        setState(() => _dragPosition = 0);
                      }
                    },
                    child: Container(
                      width: _thumbSize,
                      height: _thumbSize,
                      decoration: BoxDecoration(
                        color: widget.color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(
                        _completed
                            ? Icons.check_rounded
                            : Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Info pill — shown while en route, before arriving at the destination
// =============================================================================

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Supporting widgets (unchanged helpers)
// =============================================================================

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.arrow_back_rounded,
            color: AppTheme.nightBlue,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.scrollController, required this.child});
  final ScrollController scrollController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Color(0x22000000),
              blurRadius: 20,
              offset: Offset(0, -4)),
        ],
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _SheetSectionLabel extends StatelessWidget {
  const _SheetSectionLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.oceanBlue),
        const SizedBox(width: 5),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.oceanBlue,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.address,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.nightBlue,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({required this.mobile});
  final String mobile;

  Future<void> _call() async {
    final digits = mobile.replaceAll(RegExp(r'\s+'), '');
    await launchUrl(Uri.parse('tel:$digits'));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _call,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          shape: BoxShape.circle,
          border:
              Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
        ),
        child: const Icon(Icons.phone_rounded,
            color: Color(0xFF4CAF50), size: 18),
      ),
    );
  }
}

// =============================================================================
// Route data
// =============================================================================

class _RouteData {
  const _RouteData({required this.points, required this.distanceMeters});
  final List<LatLng> points;
  final double distanceMeters;
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            height: 18,
            decoration: BoxDecoration(
              color: AppTheme.oceanBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
          )
              .animate(onPlay: (controller) => controller.repeat())
              .shimmer(
                duration: 1000.ms,
                color: AppTheme.oceanBlue.withValues(alpha: 0.06),
              ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.oceanBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
              )
                  .animate(onPlay: (controller) => controller.repeat())
                  .shimmer(
                    duration: 1000.ms,
                    color: AppTheme.oceanBlue.withValues(alpha: 0.06),
                  ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppTheme.oceanBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    )
                        .animate(onPlay: (controller) => controller.repeat())
                        .shimmer(
                          duration: 1000.ms,
                          color: AppTheme.oceanBlue.withValues(alpha: 0.06),
                        ),
                    const SizedBox(height: 8),
                    Container(
                      width: 150,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppTheme.oceanBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    )
                        .animate(onPlay: (controller) => controller.repeat())
                        .shimmer(
                          duration: 1000.ms,
                          color: AppTheme.oceanBlue.withValues(alpha: 0.04),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
