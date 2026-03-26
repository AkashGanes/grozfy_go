import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';

class SearchResult {
  final String displayName;
  final double lat;
  final double lon;

  SearchResult({
    required this.displayName,
    required this.lat,
    required this.lon,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      displayName: json['display_name'] ?? '',
      lat: double.tryParse(json['lat']?.toString() ?? '0') ?? 0,
      lon: double.tryParse(json['lon']?.toString() ?? '0') ?? 0,
    );
  }
}

class CurrentLocationPickerScreen extends StatefulWidget {
  const CurrentLocationPickerScreen({super.key});

  @override
  State<CurrentLocationPickerScreen> createState() =>
      _CurrentLocationPickerScreenState();
}

class _CurrentLocationPickerScreenState
    extends State<CurrentLocationPickerScreen>
    with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  LatLng _selectedPoint = const LatLng(28.6139, 77.2090);
  bool _loading = true;
  bool _saving = false;
  bool _searching = false;
  String? _error;
  String _addressLabel = 'Selecting location...';
  List<SearchResult> _searchResults = [];
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = AppScope.of(context);
      if (app.hasSelectedLocation &&
          app.currentLatitude != null &&
          app.currentLongitude != null) {
        _selectedPoint = LatLng(app.currentLatitude!, app.currentLongitude!);
        _addressLabel = app.currentLocationLabel ?? 'Selected location';
        _loading = false;
        _moveMapToSelected();
        setState(() {});
      } else {
        _checkLocationStatus();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLocationStatus();
    }
  }

  Future<void> _checkLocationStatus() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final LocationPermission permission = await Geolocator.checkPermission();
    
    if (!mounted) return;
    
    final app = AppScope.of(context);
    final bool hasSavedLocation = app.hasSelectedLocation && 
        app.currentLatitude != null && 
        app.currentLongitude != null;

    if (serviceEnabled && 
        (permission == LocationPermission.always || 
         permission == LocationPermission.whileInUse)) {
      // If GPS is enabled and permission granted
      if (!hasSavedLocation) {
        // No saved location - auto load current GPS
        _loadCurrentLocation();
      } else if (_error != null) {
        // Has saved location but had error - retry
        _loadCurrentLocation();
      } else if (_loading) {
        // Has saved location, no error - just stop loading
        setState(() => _loading = false);
      }
    } else {
      // GPS is disabled or permission denied
      setState(() {
        _loading = false;
        if (_error == null) {
          if (!serviceEnabled) {
            _error = 'Location service is disabled. Please enable GPS.';
          } else if (permission == LocationPermission.denied) {
            _error = 'Location permission denied. Please allow access.';
          } else if (permission == LocationPermission.deniedForever) {
            _error = 'Location permission permanently denied. Open settings to enable it.';
          }
          _addressLabel = 'Tap on map to select location';
        }
      });
    }
  }

  Future<void> _loadCurrentLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _loading = false;
          _error = 'Location service is disabled. Please enable GPS.';
          _addressLabel = 'Tap on map to select location';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        setState(() {
          _loading = false;
          _error = 'Location permission denied. Please allow access.';
          _addressLabel = 'Tap on map to select location';
        });
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _loading = false;
          _error = 'Location permission permanently denied. Open settings to enable it.';
          _addressLabel = 'Tap on map to select location';
        });
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final LatLng current = LatLng(position.latitude, position.longitude);
      setState(() {
        _selectedPoint = current;
        _loading = false;
        _error = null;
        _addressLabel = 'Getting address...';
      });
      _moveMapToSelected();
      await _reverseGeocode(position.latitude, position.longitude);
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'Unable to fetch current location. Tap on map to select manually.';
        _addressLabel = 'Tap on map to select location';
      });
    }
  }

  void _onMapTap(LatLng point) {
    setState(() {
      _selectedPoint = point;
      _addressLabel = 'Getting address...';
      _searchResults = [];
    });
    _reverseGeocode(point.latitude, point.longitude);
  }

  DateTime? _lastReverseGeocodeTime;
  Timer? _debounceTimer;

  Future<void> _reverseGeocode(double lat, double lng) async {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performReverseGeocode(lat, lng);
    });
  }

  Future<void> _performReverseGeocode(double lat, double lng) async {
    final now = DateTime.now();
    if (_lastReverseGeocodeTime != null) {
      final diff = now.difference(_lastReverseGeocodeTime!).inMilliseconds;
      if (diff < 1000) {
        return;
      }
    }
    _lastReverseGeocodeTime = now;
    
    final currentLat = lat;
    final currentLng = lng;
    
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$currentLat&lon=$currentLng&format=json'
      );
      
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'FlowFleetPartner/1.0'}
      );
      
      if (!mounted || _selectedPoint.latitude != currentLat || _selectedPoint.longitude != currentLng) {
        return;
      }
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String address = data['display_name'] ?? '';
        
        if (address.isNotEmpty) {
          final shortAddress = _shortenAddress(address);
          if (mounted) {
            setState(() {
              _addressLabel = shortAddress;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _addressLabel = '${currentLat.toStringAsFixed(5)}, ${currentLng.toStringAsFixed(5)}';
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _addressLabel = '${currentLat.toStringAsFixed(5)}, ${currentLng.toStringAsFixed(5)}';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _addressLabel = '${currentLat.toStringAsFixed(5)}, ${currentLng.toStringAsFixed(5)}';
        });
      }
    }
  }

  String _shortenAddress(String fullAddress) {
    final parts = fullAddress.split(', ');
    if (parts.length > 3) {
      return '${parts[0]}, ${parts[1]}, ${parts[2]}';
    }
    if (parts.length > 1) {
      return '${parts[0]}, ${parts[1]}';
    }
    return fullAddress;
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _searchAddress(query);
    });
  }

  Future<void> _searchAddress(String query) async {
    if (query.trim().length < 3) return;
    
    setState(() => _searching = true);
    
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5&countrycodes=in'
      );
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'FlowFleetPartner/1.0'}
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _searchResults = data.map((json) => SearchResult.fromJson(json)).toList();
          _searching = false;
        });
      } else {
        setState(() {
          _searchResults = [];
          _searching = false;
        });
      }
    } catch (_) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
    }
  }

  void _selectSearchResult(SearchResult result) {
    final LatLng point = LatLng(result.lat, result.lon);
    setState(() {
      _selectedPoint = point;
      _addressLabel = result.displayName;
      _searchResults = [];
      _searchController.clear();
    });
    _moveMapToSelected();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults = [];
    });
  }

  Future<void> _confirmSelection() async {
    final app = AppScope.of(context);
    setState(() => _saving = true);

    await app.setSelectedLocation(
      latitude: _selectedPoint.latitude,
      longitude: _selectedPoint.longitude,
      label: _addressLabel,
    );

    if (!mounted) {
      return;
    }

    setState(() => _saving = false);

    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
  }

  void _moveMapToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      try {
        _mapController.move(_selectedPoint, 16.0);
      } catch (_) {
        // Map may not be attached yet; initialCenter still applies.
      }
    });
  }

  void _onMapDrag(MapCamera camera, bool hasGesture) {
    if (hasGesture) {
      setState(() {
        _selectedPoint = camera.center;
        _addressLabel = 'Getting address...';
      });
      
      // Call reverse geocode - rate limiting is handled in the method
      _reverseGeocode(camera.center.latitude, camera.center.longitude);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Full-screen Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedPoint,
              initialZoom: 16.0,
              onTap: (_, LatLng point) => _onMapTap(point),
              onPositionChanged: _onMapDrag,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.delivery_partner_app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selectedPoint,
                    width: 56,
                    height: 56,
                    child: const Icon(
                      Icons.location_pin,
                      size: 48,
                      color: AppTheme.nightBlue,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Loading overlay
          if (_loading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: CircularProgressIndicator(
                  color: AppTheme.mango,
                ),
              ),
            ),

          // Header and Search Bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.nightBlue,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Select Delivery Zone',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Search Bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search area or location...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.nightBlue,
                                ),
                              ),
                            )
                          : _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: _clearSearch,
                                )
                              : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                // Search Results Dropdown
                if (_searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        return ListTile(
                          leading: const Icon(
                            Icons.location_on_outlined,
                            color: AppTheme.nightBlue,
                          ),
                          title: Text(
                            result.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () => _selectSearchResult(result),
                          dense: true,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // My Location FAB
          Positioned(
            right: 16,
            bottom: 200,
            child: FloatingActionButton(
              heroTag: 'myLocation',
              mini: true,
              backgroundColor: Colors.white,
              onPressed: _loading || _saving ? null : _loadCurrentLocation,
              child: const Icon(
                Icons.my_location_rounded,
                color: AppTheme.nightBlue,
              ),
            ),
          ),

          // Settings FAB
          Positioned(
            right: 16,
            bottom: 260,
            child: FloatingActionButton(
              heroTag: 'settings',
              mini: true,
              backgroundColor: Colors.white,
              onPressed: _saving
                  ? null
                  : () async {
                      await Geolocator.openLocationSettings();
                    },
              child: const Icon(
                Icons.settings_rounded,
                color: AppTheme.nightBlue,
              ),
            ),
          ),

          // Bottom Card with Address and Confirm Button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
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
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle indicator
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
                      const SizedBox(height: 16),

                      // Title
                      const Text(
                        'Select Delivery Zone',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.nightBlue,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Address Display
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.nightBlue.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.nightBlue.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              color: AppTheme.nightBlue,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Selected Location',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _addressLabel,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.nightBlue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!_loading)
                              IconButton(
                                icon: const Icon(
                                  Icons.edit_rounded,
                                  size: 20,
                                ),
                                onPressed: () {
                                  // Allow manual edit if needed
                                },
                              ),
                          ],
                        ),
                      ),

                      // Error message with actions
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_off_rounded,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Location Required',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        await Geolocator.openLocationSettings();
                                      },
                                      icon: const Icon(
                                        Icons.gps_fixed_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Turn On GPS'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red,
                                        side: const BorderSide(color: Colors.red),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _loadCurrentLocation,
                                      icon: const Icon(
                                        Icons.refresh_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Retry'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red,
                                        side: const BorderSide(color: Colors.red),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Confirm Button
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: (_loading || _saving || _error != null)
                              ? null
                              : _confirmSelection,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _error != null
                                ? Colors.grey
                                : AppTheme.nightBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(_error != null
                                        ? Icons.location_off_rounded
                                        : Icons.check_circle_rounded),
                                    const SizedBox(width: 8),
                                    Text(
                                      _error != null
                                          ? 'Location Required'
                                          : 'Confirm Location',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
