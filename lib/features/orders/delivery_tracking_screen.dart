import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/services/api_service.dart';
import '../../core/state/app_scope.dart';

class DeliveryTrackingScreen extends StatefulWidget {
  final String? deliveryName;
  final String? customerName;
  final String? storeName;
  final String? contactNumber;
  final String? dropAddress;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropLat;
  final double? dropLng;

  const DeliveryTrackingScreen({
    super.key,
    this.deliveryName,
    this.customerName,
    this.storeName,
    this.contactNumber,
    this.dropAddress,
    this.pickupLat,
    this.pickupLng,
    this.dropLat,
    this.dropLng,
  });

  @override
  State<DeliveryTrackingScreen> createState() => _DeliveryTrackingScreenState();
}

class _DeliveryTrackingScreenState extends State<DeliveryTrackingScreen> {
  final ApiService _apiService = ApiService();
  late final MapController _mapController;
  StreamSubscription<Position>? _positionStream;

  String _deliveryName = '';
  String _customerName = '';
  String _storeName = '';
  String _contactNumber = '';
  String _dropAddress = '';
  double? _pickupLat;
  double? _pickupLng;
  double? _dropLat;
  double? _dropLng;

  LatLng _currentLocation = const LatLng(11.1271, 78.6569);
  LatLng? _destination;
  List<LatLng> _polylineCoordinates = [];
  List<Marker> _markers = [];
  double _currentHeading = 0;
  DateTime? _lastRouteFetchAt;
  bool _isMapReady = false;
  bool _isFetchingRoute = false;

  bool _isTracking = false;
  bool _isMinimized = false;
  bool _isLoading = true;
  double _distanceToDestination = 0;
  bool _hasArrived = false;
  String? _errorMessage;

  final TextEditingController _demoLatController = TextEditingController(
    text: '11.1271',
  );
  final TextEditingController _demoLngController = TextEditingController(
    text: '78.6569',
  );

  static const double _arrivalThreshold = 50.0;
  static const Color _primaryColor = Color(0xFF44b180);
  static const Color _secondaryColor = Color(0xFF2E7D32);
  static const String _osrmBaseUrl = kDebugMode
      ? 'https://router.project-osrm.org/route/v1/driving'
      : 'TODO: Replace with self-hosted OSRM server URL';
  static const Duration _routeRefreshInterval = Duration(seconds: 20);
  static const int _maxRoutePoints = 400;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadDeliveryData();
    _initializeLocation();
  }

  void _loadDeliveryData() {
    _deliveryName = widget.deliveryName ?? '';
    _customerName = widget.customerName ?? '';
    _storeName = widget.storeName ?? '';
    _contactNumber = widget.contactNumber ?? '';
    _dropAddress = widget.dropAddress ?? '';
    _pickupLat = widget.pickupLat;
    _pickupLng = widget.pickupLng;
    _dropLat = widget.dropLat;
    _dropLng = widget.dropLng;

    if (_dropLat != null && _dropLng != null) {
      _destination = LatLng(_dropLat!, _dropLng!);
    }

    if (_destination != null) {
      _demoLatController.text = _dropLat?.toStringAsFixed(4) ?? '';
      _demoLngController.text = _dropLng?.toStringAsFixed(4) ?? '';
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController.dispose();
    _demoLatController.dispose();
    _demoLngController.dispose();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final hasPermission = await _checkAndRequestLocationPermission();

    if (!hasPermission) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Location permission is required for delivery tracking';
      });
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _isLoading = false;
      });
      _updateMarkers();

      if (_isMapReady) {
        _mapController.move(_currentLocation, 16.0);
      }

      if (_destination != null) {
        _getRoutePoints();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not get GPS: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      if (_destination != null) {
        _getRoutePoints();
      }
    }
  }

  Future<bool> _checkAndRequestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        _showLocationServiceDialog();
      }
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        _showPermissionDeniedDialog();
      }
      return false;
    }

    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.orange),
            SizedBox(width: 8),
            Text('Location Services'),
          ],
        ),
        content: const Text(
          'Please enable location services to use delivery tracking. '
          'Go to Settings > Location and turn it on.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openLocationSettings();
            },
            child: const Text('Open Settings'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _errorMessage = 'Location services disabled';
              });
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_disabled, color: Colors.red),
            SizedBox(width: 8),
            Text('Permission Denied'),
          ],
        ),
        content: const Text(
          'Location permission is required for delivery tracking. '
          'Please grant permission in app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _errorMessage = 'Location permission denied';
              });
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _setDestination(LatLng destination) {
    setState(() {
      _destination = destination;
      _hasArrived = false;
    });
    _getRoutePoints();
    _startLiveTracking();
  }

  Future<void> _getRoutePoints() async {
    if (_destination == null || _isFetchingRoute) return;

    _isFetchingRoute = true;
    final destination = _destination!;
    try {
      final _RouteData? routeData = await _fetchOsrmRoute(
        from: _currentLocation,
        to: destination,
      );
      if (!mounted) return;

      if (routeData != null && routeData.points.length >= 2) {
        setState(() {
          _polylineCoordinates = routeData.points;
          _distanceToDestination = routeData.distanceMeters;
          _lastRouteFetchAt = DateTime.now();
          _updateRemainingRouteFromCurrentLocation();
        });
      } else {
        _setFallbackRoute(destination);
      }
    } catch (e) {
      debugPrint('Route fetch failed: $e');
      if (!mounted) return;
      _setFallbackRoute(destination);
    } finally {
      _isFetchingRoute = false;
    }

    _updateMarkers();
    _fitMapToRoute();
  }

  Future<_RouteData?> _fetchOsrmRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    final Uri uri =
        Uri.parse(
          '$_osrmBaseUrl/${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
        ).replace(
          queryParameters: const <String, String>{
            'overview': 'full',
            'geometries': 'geojson',
            'steps': 'false',
          },
        );

    final http.Response response = await http
        .get(uri)
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      debugPrint(
        'OSRM route request failed (${response.statusCode}): ${response.body}',
      );
      return null;
    }

    final Map<String, dynamic> payload =
        jsonDecode(response.body) as Map<String, dynamic>;
    final List<dynamic>? routes = payload['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      return null;
    }

    final Map<String, dynamic> firstRoute =
        routes.first as Map<String, dynamic>;
    final double routeDistance =
        (firstRoute['distance'] as num?)?.toDouble() ?? 0;
    final Map<String, dynamic>? geometry =
        firstRoute['geometry'] as Map<String, dynamic>?;
    final List<dynamic>? coordinates =
        geometry?['coordinates'] as List<dynamic>?;

    if (coordinates == null || coordinates.length < 2) {
      return null;
    }

    final List<LatLng> routePoints = <LatLng>[
      for (final dynamic pair in coordinates)
        if (pair is List &&
            pair.length >= 2 &&
            pair[0] is num &&
            pair[1] is num)
          LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()),
    ];

    if (routePoints.length < 2) {
      return null;
    }

    return _RouteData(
      points: _compressRoutePoints(routePoints),
      distanceMeters: routeDistance,
    );
  }

  List<LatLng> _compressRoutePoints(List<LatLng> points) {
    if (points.length <= _maxRoutePoints) {
      return points;
    }

    final int stride = max(1, (points.length / _maxRoutePoints).ceil());
    final List<LatLng> compressed = <LatLng>[];
    for (int i = 0; i < points.length; i += stride) {
      compressed.add(points[i]);
    }

    if (compressed.last != points.last) {
      compressed.add(points.last);
    }

    return compressed;
  }

  void _setFallbackRoute(LatLng destination) {
    final List<LatLng> fallbackPoints = <LatLng>[];
    const int numPoints = 30;
    for (int i = 0; i <= numPoints; i++) {
      final double lat =
          _currentLocation.latitude +
          (destination.latitude - _currentLocation.latitude) * i / numPoints;
      final double lng =
          _currentLocation.longitude +
          (destination.longitude - _currentLocation.longitude) * i / numPoints;
      fallbackPoints.add(LatLng(lat, lng));
    }

    setState(() {
      _polylineCoordinates = fallbackPoints;
      _distanceToDestination = _calculateDistance(
        _currentLocation.latitude,
        _currentLocation.longitude,
        destination.latitude,
        destination.longitude,
      );
      _lastRouteFetchAt = DateTime.now();
    });
  }

  bool _shouldRefreshRoute() {
    if (_destination == null || _isFetchingRoute) return false;
    if (_lastRouteFetchAt == null) return true;
    return DateTime.now().difference(_lastRouteFetchAt!) >=
        _routeRefreshInterval;
  }

  void _fitMapToRoute() {
    if (_polylineCoordinates.isEmpty || !_isMapReady) return;

    double minLat = _polylineCoordinates.first.latitude;
    double maxLat = _polylineCoordinates.first.latitude;
    double minLng = _polylineCoordinates.first.longitude;
    double maxLng = _polylineCoordinates.first.longitude;

    for (var point in _polylineCoordinates) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    final bounds = LatLngBounds.fromPoints([
      LatLng(minLat - 0.02, minLng - 0.02),
      LatLng(maxLat + 0.02, maxLng + 0.02),
    ]);

    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
    );
  }

  void _updateRemainingRouteFromCurrentLocation() {
    if (_polylineCoordinates.length < 2) return;

    final int nearestIndex = _findNearestRoutePointIndex(_currentLocation);
    final int nextIndex = min(
      nearestIndex + 1,
      _polylineCoordinates.length - 1,
    );

    final List<LatLng> remainingRoute = <LatLng>[
      _currentLocation,
      ..._polylineCoordinates.sublist(nextIndex),
    ];

    if (_destination != null) {
      final LatLng lastPoint = remainingRoute.last;
      final double metersToDestination = _calculateDistance(
        lastPoint.latitude,
        lastPoint.longitude,
        _destination!.latitude,
        _destination!.longitude,
      );
      if (metersToDestination > 3) {
        remainingRoute.add(_destination!);
      }
    }

    _polylineCoordinates = remainingRoute;
  }

  int _findNearestRoutePointIndex(LatLng from) {
    int nearestIndex = 0;
    double nearestDistance = double.infinity;

    for (int i = 0; i < _polylineCoordinates.length; i++) {
      final LatLng point = _polylineCoordinates[i];
      final double distance = _calculateDistance(
        from.latitude,
        from.longitude,
        point.latitude,
        point.longitude,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }

    return nearestIndex;
  }

  void _startLiveTracking() {
    if (_isTracking) return;

    setState(() {
      _isTracking = true;
    });

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            final LatLng nextLocation = LatLng(
              position.latitude,
              position.longitude,
            );
            final double movedMeters = _calculateDistance(
              _currentLocation.latitude,
              _currentLocation.longitude,
              nextLocation.latitude,
              nextLocation.longitude,
            );
            final double nextHeading = movedMeters > 2
                ? _calculateBearing(_currentLocation, nextLocation)
                : _currentHeading;

            setState(() {
              _currentLocation = nextLocation;
              _currentHeading = nextHeading;
              _updateRemainingRouteFromCurrentLocation();
            });

            _updateMarkers();
            _checkArrival();

            if (_isMapReady && _isTracking) {
              _mapController.move(_currentLocation, 16.0);
            }

            if (_shouldRefreshRoute()) {
              _getRoutePoints();
            }
          },
          onError: (e) {
            debugPrint('Location stream error: $e');
          },
        );
  }

  void _stopLiveTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    setState(() {
      _isTracking = false;
    });
  }

  void _updateMarkers() {
    _markers = [
      Marker(
        point: _currentLocation,
        width: 52,
        height: 52,
        child: Transform.rotate(
          angle: _toRadians(_currentHeading),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.directions_bike,
              color: Colors.blue,
              size: 30,
            ),
          ),
        ),
      ),
    ];

    if (_pickupLat != null && _pickupLng != null) {
      _markers.add(
        Marker(
          point: LatLng(_pickupLat!, _pickupLng!),
          width: 52,
          height: 52,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.store, color: Colors.orange, size: 30),
          ),
        ),
      );
    }

    if (_destination != null) {
      _markers.add(
        Marker(
          point: _destination!,
          width: 52,
          height: 52,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.location_on, color: Colors.red, size: 34),
          ),
        ),
      );
    }
  }

  void _checkArrival() {
    if (_destination == null || _hasArrived) return;

    final distance = _calculateDistance(
      _currentLocation.latitude,
      _currentLocation.longitude,
      _destination!.latitude,
      _destination!.longitude,
    );
    final bool arrived = distance < _arrivalThreshold;

    setState(() {
      _distanceToDestination = distance;
      _hasArrived = arrived;
    });

    if (arrived) {
      _stopLiveTracking();
    }
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000;
    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);
    double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degree) => degree * pi / 180;

  double _calculateBearing(LatLng from, LatLng to) {
    final double lat1 = _toRadians(from.latitude);
    final double lat2 = _toRadians(to.latitude);
    final double dLon = _toRadians(to.longitude - from.longitude);
    final double y = sin(dLon) * cos(lat2);
    final double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    final double bearing = atan2(y, x);
    return (bearing * 180 / pi + 360) % 360;
  }

  Future<void> _callCustomer(String phoneNumber) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final status = await Permission.phone.request();

    if (status.isGranted) {
      final String phoneUrl = 'tel:$phoneNumber';
      final Uri launchUri = Uri.parse(phoneUrl);

      try {
        if (await canLaunchUrl(launchUri)) {
          await launchUrl(launchUri, mode: LaunchMode.externalApplication);
        } else {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('No phone app found. Number: $phoneNumber'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error launching phone: $e');
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } else if (status.isDenied) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Phone permission denied. Please enable it in settings.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      await openAppSettings();
    } else if (status.isPermanentlyDenied) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Phone permission permanently denied. Please enable in settings.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      await openAppSettings();
    }
  }

  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Delivery'),
        content: const Text('Are you sure you want to cancel this delivery?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelDelivery();
            },
            child: const Text(
              'Yes, Cancel',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelDelivery() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final app = AppScope.of(context);
    final navigator = Navigator.of(context);

    scaffoldMessenger.showSnackBar(
      SnackBar(content: Text('Cancelling delivery $_deliveryName...')),
    );

    final success = await _apiService.updateDeliveryStatus(
      _deliveryName,
      'Cancelled',
    );

    if (!mounted) return;

    if (!success) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to cancel on server. Cancelling locally.'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    app.clearActiveOrder();
    _stopLiveTracking();
    navigator.pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Delivery cancelled')),
    );
  }

  Future<void> _confirmDelivery() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final app = AppScope.of(context);
    final navigator = Navigator.of(context);

    scaffoldMessenger.showSnackBar(
      SnackBar(content: Text('Confirming delivery $_deliveryName...')),
    );

    final success = await _apiService.updateDeliveryStatus(
      _deliveryName,
      'Delivered',
    );

    if (!mounted) return;

    if (!success) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to update server. Saving locally.'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    app.updateOrderStatus(OrderProgressStatus.delivered);
    _stopLiveTracking();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            SizedBox(width: 8),
            Text('Delivered!'),
          ],
        ),
        content: const Text('Order delivered successfully!'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              navigator.pushNamedAndRemoveUntil(
                AppRoutes.dashboard,
                (route) => false,
              );
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showDemoLocationPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Set Delivery Location',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter coordinates for testing',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _demoLatController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Latitude',
                      hintText: '28.6139',
                      prefixIcon: const Icon(Icons.location_on),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _demoLngController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Longitude',
                      hintText: '77.2090',
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                final lat = double.tryParse(_demoLatController.text);
                final lng = double.tryParse(_demoLngController.text);
                if (lat != null &&
                    lng != null &&
                    lat >= -90 &&
                    lat <= 90 &&
                    lng >= -180 &&
                    lng <= 180) {
                  _setDestination(LatLng(lat, lng));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Route calculated! Start navigation.'),
                      backgroundColor: _primaryColor,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter valid coordinates'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Set Location',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _refreshLocation() async {
    setState(() {
      _isLoading = true;
    });
    await _initializeLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: 16.0,
              onMapReady: () {
                _isMapReady = true;
                _updateMarkers();
                if (_polylineCoordinates.isNotEmpty) {
                  _fitMapToRoute();
                } else {
                  _mapController.move(_currentLocation, 16.0);
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
                    Polyline(
                      points: _polylineCoordinates,
                      color: Colors.blue,
                      strokeWidth: 6.0,
                    ),
                  ],
                ),
              MarkerLayer(markers: _markers),
            ],
          ),

          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: CircularProgressIndicator(color: _primaryColor),
              ),
            ),

          if (_errorMessage != null && !_isLoading)
            Positioned(
              top: 60,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                      TextButton(
                        onPressed: _refreshLocation,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.my_location, color: _primaryColor),
                      onPressed: () {
                        if (_isMapReady) {
                          _mapController.move(_currentLocation, 16.0);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (kDebugMode)
            Positioned(
              top: 100,
              right: 16,
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.edit_location,
                        color: _primaryColor,
                      ),
                      onPressed: _showDemoLocationPicker,
                      tooltip: 'Set delivery location (Debug only)',
                    ),
                  ),
                ],
              ),
            ),

          DraggableScrollableSheet(
            key: ValueKey(_isMinimized),
            initialChildSize: _isMinimized ? 0.15 : 0.38,
            minChildSize: 0.15,
            maxChildSize: 0.7,
            builder: (context, scrollController) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      if (_deliveryName.isNotEmpty ||
                          _storeName.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _primaryColor.withValues(alpha: 0.1),
                                _secondaryColor.withValues(alpha: 0.1),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: _primaryColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.shopping_bag,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _storeName.isNotEmpty
                                              ? _storeName
                                              : _deliveryName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (_deliveryName.isNotEmpty)
                                          Text(
                                            'Order $_deliveryName',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.person,
                                    color: Colors.grey,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _customerName.isNotEmpty
                                        ? _customerName
                                        : 'Customer',
                                  ),
                                  const Spacer(),
                                  const Icon(
                                    Icons.location_on,
                                    color: Colors.grey,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _dropAddress.isNotEmpty
                                          ? _dropAddress
                                          : 'Delivery location',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.social_distance,
                                        color: Colors.grey[600],
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Distance',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _distanceToDestination > 0
                                        ? '${(_distanceToDestination / 1000).toStringAsFixed(1)} km'
                                        : '-- km',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 22,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 50,
                              color: Colors.grey[300],
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.directions_car,
                                          color: Colors.grey[600],
                                          size: 16,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Status',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          _hasArrived
                                              ? Icons.check_circle
                                              : (_isTracking
                                                    ? Icons.directions_bike
                                                    : Icons.pending),
                                          color: _hasArrived
                                              ? Colors.green
                                              : (_isTracking
                                                    ? _primaryColor
                                                    : Colors.orange),
                                          size: 22,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _hasArrived
                                              ? 'Arrived!'
                                              : (_isTracking
                                                    ? 'En Route'
                                                    : 'Ready'),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                            color: _hasArrived
                                                ? Colors.green
                                                : (_isTracking
                                                      ? _primaryColor
                                                      : Colors.orange),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _contactNumber.isNotEmpty
                                  ? () => _callCustomer(_contactNumber)
                                  : null,
                              icon: const Icon(Icons.call),
                              label: const Text('Call'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _showCancelDialog,
                              icon: const Icon(Icons.cancel_outlined),
                              label: const Text('Cancel'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _destination != null
                              ? (_isTracking
                                    ? _stopLiveTracking
                                    : _startLiveTracking)
                              : (kDebugMode
                                    ? _showDemoLocationPicker
                                    : () {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'No delivery location available',
                                            ),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _destination == null
                                ? _primaryColor
                                : (_isTracking ? Colors.orange : _primaryColor),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _destination == null
                                    ? Icons.location_searching
                                    : (_isTracking
                                          ? Icons.stop
                                          : Icons.navigation),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _destination == null
                                    ? 'Select Delivery Location'
                                    : (_isTracking
                                          ? 'Stop Navigation'
                                          : 'Start Navigation'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (_hasArrived) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _confirmDelivery,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle),
                                SizedBox(width: 8),
                                Text(
                                  'Confirm Delivery',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 24,
            left: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () => setState(() => _isMinimized = !_isMinimized),
                icon: Icon(
                  _isMinimized ? Icons.fullscreen : Icons.minimize,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteData {
  const _RouteData({required this.points, required this.distanceMeters});

  final List<LatLng> points;
  final double distanceMeters;
}
