import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/call_utils.dart';
import '../../core/widgets/app_shell.dart';
import 'widgets/order_timer_widget.dart';

class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;

  LatLng _partnerLocation = const LatLng(0, 0);
  double _currentHeading = 0;
  List<LatLng> _routePoints = [];
  double _distanceMeters = 0;
  bool _isMapReady = false;
  bool _isTracking = false;
  bool _isFetchingRoute = false;
  bool _hasInitialPosition = false;
  DateTime? _lastRouteFetchAt;

  static const String _osrmBase =
      'https://router.project-osrm.org/route/v1/driving';
  static const Duration _routeRefreshInterval = Duration(seconds: 20);
  static const int _maxRoutePoints = 400;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initTracking());
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initTracking() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled || !mounted) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever || !mounted) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      setState(() {
        _partnerLocation = LatLng(position.latitude, position.longitude);
        _hasInitialPosition = true;
      });
      final order = AppScope.of(context).activeOrder;
      if (order != null) {
        _fetchRoute(LatLng(order.latitude, order.longitude));
      }
    } catch (_) {}

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((position) {
      if (!mounted) return;
      final next = LatLng(position.latitude, position.longitude);
      final moved = _calcDistance(
        _partnerLocation.latitude,
        _partnerLocation.longitude,
        next.latitude,
        next.longitude,
      );
      final heading =
          moved > 2 ? _calcBearing(_partnerLocation, next) : _currentHeading;

      setState(() {
        _currentHeading = heading;
        _partnerLocation = next;
        _isTracking = true;
        _hasInitialPosition = true;
        _trimRoute();
      });

      if (_isMapReady) {
        _mapController.move(_partnerLocation, _mapController.camera.zoom);
      }

      final order = AppScope.of(context).activeOrder;
      _maybeRefreshRoute(order);
    });

    setState(() => _isTracking = true);
  }

  Future<void> _fetchRoute(LatLng destination) async {
    if (_isFetchingRoute || !_hasInitialPosition) return;
    _isFetchingRoute = true;

    try {
      final uri = Uri.parse(
        '$_osrmBase/${_partnerLocation.longitude},${_partnerLocation.latitude}'
        ';${destination.longitude},${destination.latitude}',
      ).replace(
        queryParameters: const {
          'overview': 'full',
          'geometries': 'geojson',
          'steps': 'false',
        },
      );

      final response =
          await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) throw Exception('OSRM ${response.statusCode}');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) throw Exception('No routes');

      final route = routes.first as Map<String, dynamic>;
      final dist = (route['distance'] as num?)?.toDouble() ?? 0;
      final coords =
          (route['geometry'] as Map<String, dynamic>?)?['coordinates']
              as List<dynamic>?;
      if (coords == null || coords.length < 2) throw Exception('No coords');

      final points = <LatLng>[
        for (final p in coords)
          if (p is List && p.length >= 2 && p[0] is num && p[1] is num)
            LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()),
      ];
      if (points.length < 2) throw Exception('Too few points');

      if (!mounted) return;
      setState(() {
        _routePoints = _compress(points);
        _distanceMeters = dist;
        _lastRouteFetchAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _routePoints = [_partnerLocation, destination];
        _distanceMeters = _calcDistance(
          _partnerLocation.latitude,
          _partnerLocation.longitude,
          destination.latitude,
          destination.longitude,
        );
        _lastRouteFetchAt = DateTime.now();
      });
    } finally {
      _isFetchingRoute = false;
    }

    if (_isMapReady && _routePoints.length >= 2) {
      _fitToRoute();
    }
  }

  void _maybeRefreshRoute(DeliveryOrder? order) {
    if (order == null || _isFetchingRoute) return;
    final dest = LatLng(order.latitude, order.longitude);
    if (_lastRouteFetchAt == null) {
      _fetchRoute(dest);
    } else if (DateTime.now().difference(_lastRouteFetchAt!) >=
        _routeRefreshInterval) {
      _fetchRoute(dest);
    }
  }

  void _trimRoute() {
    if (_routePoints.length < 2) return;
    int nearest = 0;
    double nearestDist = double.infinity;
    for (int i = 0; i < _routePoints.length; i++) {
      final d = _calcDistance(
        _partnerLocation.latitude,
        _partnerLocation.longitude,
        _routePoints[i].latitude,
        _routePoints[i].longitude,
      );
      if (d < nearestDist) {
        nearestDist = d;
        nearest = i;
      }
    }
    final next = min(nearest + 1, _routePoints.length - 1);
    _routePoints = [_partnerLocation, ..._routePoints.sublist(next)];
  }

  void _fitToRoute() {
    if (_routePoints.isEmpty) return;
    double minLat = _routePoints.first.latitude,
        maxLat = _routePoints.first.latitude;
    double minLng = _routePoints.first.longitude,
        maxLng = _routePoints.first.longitude;
    for (final p in _routePoints) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([
          LatLng(minLat - 0.005, minLng - 0.005),
          LatLng(maxLat + 0.005, maxLng + 0.005),
        ]),
        padding: const EdgeInsets.fromLTRB(48, 80, 48, 320),
      ),
    );
  }

  List<LatLng> _compress(List<LatLng> pts) {
    if (pts.length <= _maxRoutePoints) return pts;
    final stride = max(1, (pts.length / _maxRoutePoints).ceil());
    final result = <LatLng>[];
    for (int i = 0; i < pts.length; i += stride) {
      result.add(pts[i]);
    }
    if (result.last != pts.last) result.add(pts.last);
    return result;
  }

  double _calcDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _calcBearing(LatLng from, LatLng to) {
    final lat1 = _rad(from.latitude), lat2 = _rad(to.latitude);
    final dLon = _rad(to.longitude - from.longitude);
    final y = sin(dLon) * cos(lat2);
    final x =
        cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  double _rad(double deg) => deg * pi / 180;

  String _formatDist(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.toStringAsFixed(0)} m';
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final app = AppScope.of(context);
    final order = app.activeOrder;

    if (order == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.track_changes,
                size: 64,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                'No active order to track',
                style: TextStyle(
                  fontSize: 16,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context)
                    .pushReplacementNamed(AppRoutes.dashboard),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      );
    }

    final destination = LatLng(order.latitude, order.longitude);
    final distanceM = _hasInitialPosition
        ? _calcDistance(
            _partnerLocation.latitude,
            _partnerLocation.longitude,
            destination.latitude,
            destination.longitude,
          )
        : _distanceMeters;

    return AppShell(
      title: 'Track Order ${order.orderId}',
      subtitle: 'Real-time tracking visible to customer & admin',
      // Map + DraggableScrollableSheet need bounded height; AppShell's
      // default SingleChildScrollView wrapper denies that and crashes
      // the engine on push.
      scrollable: false,
      padding: EdgeInsets.zero,
      actions: [
        if (app.isOrderTimerRunning)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: OrderTimerWidget(),
          ),
      ],
      child: Stack(
        children: [
          // ── Full-screen map ──────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: destination,
              initialZoom: 15,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.drag |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom,
              ),
              onMapReady: () {
                _isMapReady = true;
                if (_routePoints.length >= 2) {
                  _fitToRoute();
                } else if (_hasInitialPosition) {
                  _mapController.move(_partnerLocation, 15);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: isDark
                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                    : 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: isDark ? const ['a', 'b', 'c', 'd'] : const [],
                userAgentPackageName: 'com.lyncspace.grozfy_go',
              ),
              if (_routePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: AppTheme.oceanBlue,
                      strokeWidth: 5,
                      borderColor: Colors.white.withValues(alpha: 0.5),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // Destination pin
                  Marker(
                    point: destination,
                    width: 52,
                    height: 52,
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.35),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: Colors.red,
                        size: 32,
                      ),
                    ),
                  ),
                  // Partner / bike marker (bearing-rotated)
                  if (_hasInitialPosition)
                    Marker(
                      point: _partnerLocation,
                      width: 52,
                      height: 52,
                      child: Transform.rotate(
                        angle: _currentHeading * pi / 180,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.oceanBlue,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.oceanBlue.withValues(alpha: 0.45),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.delivery_dining_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // ── Top overlay bar ──────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _MapIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: _isTracking ? Colors.green : Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isTracking ? 'Live Tracking' : 'Getting GPS…',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          _StatusChip(status: order.orderStatus),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _MapIconButton(
                    icon: Icons.my_location_rounded,
                    color: AppTheme.oceanBlue,
                    onTap: () {
                      if (_isMapReady && _hasInitialPosition) {
                        _mapController.move(_partnerLocation, 16);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          // ── Distance badge ────────────────────────────────────────────
          if (_hasInitialPosition || _distanceMeters > 0)
            Positioned(
              top: MediaQuery.of(context).padding.top + 74,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.straighten_rounded,
                        size: 15,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatDist(distanceM),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '  to destination',
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Bottom info sheet ─────────────────────────────────────────
          DraggableScrollableSheet(
            initialChildSize: 0.38,
            minChildSize: 0.14,
            maxChildSize: 0.76,
            builder: (context, scrollController) => Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Order title row
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.oceanBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.shopping_bag_rounded,
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
                              'Order #${order.orderId}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              order.storeName.isNotEmpty
                                  ? order.storeName
                                  : 'Delivery',
                              style: TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Distance + GPS tiles
                  Row(
                    children: [
                      Expanded(
                        child: _InfoTile(
                          icon: Icons.straighten_rounded,
                          label: 'Distance',
                          value: _formatDist(distanceM),
                          color: AppTheme.oceanBlue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _InfoTile(
                          icon: _isTracking
                              ? Icons.gps_fixed
                              : Icons.gps_not_fixed,
                          label: 'GPS',
                          value: _isTracking ? 'Live' : 'Searching…',
                          color: _isTracking ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  const Divider(height: 1),
                  const SizedBox(height: 14),

                  // Customer details
                  _DetailRow(
                    icon: Icons.person_rounded,
                    label: 'Customer',
                    value: order.customerName,
                  ),
                  const SizedBox(height: 8),
                  _DetailRow(
                    icon: Icons.phone_rounded,
                    label: 'Phone',
                    value: order.customerPhone,
                  ),
                  const SizedBox(height: 8),
                  _DetailRow(
                    icon: Icons.home_rounded,
                    label: 'Address',
                    value: order.deliveryAddress,
                  ),
                  if (order.drop.isNotEmpty && order.drop != order.deliveryAddress) ...[
                    const SizedBox(height: 8),
                    _DetailRow(
                      icon: Icons.flag_rounded,
                      label: 'Drop',
                      value: order.drop,
                    ),
                  ],
                  if (order.reachedStoreAt != null) ...[
                    const SizedBox(height: 8),
                    _DetailRow(
                      icon: Icons.access_time_rounded,
                      label: 'Reached',
                      value: _formatTime(order.reachedStoreAt!),
                    ),
                  ],
                  const SizedBox(height: 16),

                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // Delivery progress timeline
                  _DeliveryProgressTimeline(status: order.orderStatus),
                  const SizedBox(height: 20),

                  // Call customer button
                  if (order.customerPhone.isNotEmpty ||
                      order.contactNumber.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => makePhoneCall(
                          context,
                          order.customerPhone.isNotEmpty
                              ? order.customerPhone
                              : order.contactNumber,
                          label: order.customerName,
                        ),
                        icon: const Icon(Icons.call_rounded),
                        label: const Text('Call Customer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.oceanBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),

                  if (kDebugMode) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'GPS: ${_hasInitialPosition ? '${_partnerLocation.latitude.toStringAsFixed(5)}, ${_partnerLocation.longitude.toStringAsFixed(5)}' : 'waiting…'}\n'
                        'Dest: ${destination.latitude.toStringAsFixed(5)}, ${destination.longitude.toStringAsFixed(5)}\n'
                        'Route points: ${_routePoints.length}',
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _MapIconButton extends StatelessWidget {
  const _MapIconButton({
    required this.icon,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: color ?? scheme.onSurface, size: 22),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: _color(status),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        AppScope.of(context).orderStatusLabel(status),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _color(OrderStatus s) {
    switch (s) {
      case OrderStatus.accepted:
        return Colors.blue;
      case OrderStatus.reachedPickup:
        return Colors.orange;
      case OrderStatus.pickedUp:
        return Colors.purple;
      case OrderStatus.outForDelivery:
        return AppTheme.oceanBlue;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 17,
          color: scheme.onSurface.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _DeliveryProgressTimeline extends StatelessWidget {
  const _DeliveryProgressTimeline({required this.status});

  final OrderStatus status;

  static const _steps = [
    (label: 'Accepted', icon: Icons.task_alt_rounded),
    (label: 'Reached', icon: Icons.store_rounded),
    (label: 'Picked', icon: Icons.inventory_2_rounded),
    (label: 'En Route', icon: Icons.delivery_dining_rounded),
    (label: 'Delivered', icon: Icons.home_rounded),
  ];

  static const _flow = [
    OrderStatus.accepted,
    OrderStatus.reachedPickup,
    OrderStatus.pickedUp,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
  ];

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final currentIndex = _flow.indexOf(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Delivery Progress',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 14),
        Stack(
          alignment: Alignment.center,
          children: [
            // Connector lines — centred vertically on the circles (circle height 36, top pad ~0)
            Positioned(
              top: 18,
              left: 20,
              right: 20,
              child: Row(
                children: List.generate(_steps.length - 1, (i) {
                  return Expanded(
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: i < currentIndex
                            ? Colors.green
                            : scheme.onSurface.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Step nodes
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(_steps.length, (i) {
                final isActive = i <= currentIndex;
                final isCurrent = i == currentIndex;
                final step = _steps[i];

                return Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isActive
                            ? (isCurrent ? AppTheme.oceanBlue : Colors.green)
                            : scheme.onSurface.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        boxShadow: isCurrent
                            ? [
                                BoxShadow(
                                  color: AppTheme.oceanBlue.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        isActive && !isCurrent
                            ? Icons.check_rounded
                            : step.icon,
                        color: isActive
                            ? Colors.white
                            : scheme.onSurface.withValues(alpha: 0.4),
                        size: 17,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      step.label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                        color: isActive
                            ? scheme.onSurface
                            : scheme.onSurface.withValues(alpha: 0.5),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ],
    );
  }
}
