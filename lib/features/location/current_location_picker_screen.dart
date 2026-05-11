import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';

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
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen(
      (ServiceStatus status) {
        if (!mounted) return;
        if (status == ServiceStatus.enabled) {
          // Only auto-fetch when we were showing an error; leave a working
          // user-selected location untouched if GPS briefly cycles.
          if (_error != null) _loadCurrentLocation();
        } else {
          setState(() {
            _error = 'Location service is disabled. Please enable GPS.';
            _addressLabel = 'Tap on map to select location';
          });
        }
      },
    );
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
    _serviceStatusSubscription?.cancel();
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
        if (!serviceEnabled) {
          _error = 'Location service is disabled. Please enable GPS.';
        } else if (permission == LocationPermission.denied) {
          _error = 'Location permission denied. Please allow access.';
        } else if (permission == LocationPermission.deniedForever) {
          _error = 'Location permission permanently denied. Open settings to enable it.';
        }
        _addressLabel = 'Tap on map to select location';
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
        headers: {'User-Agent': 'GrozfyGo/1.0'}
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
        headers: {'User-Agent': 'GrozfyGo/1.0'}
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF12141C) : const Color(0xFFF7F9FC);
    final cardBg = isDark ? const Color(0xFF1B1E2A) : Colors.white;
    final cardBorder =
        isDark ? const Color(0xFF2A2F3D) : const Color(0xFFE7EBF0);
    final textPrimary =
        isDark ? const Color(0xFFF2F4F7) : const Color(0xFF101828);
    final textSecondary =
        isDark ? const Color(0xFFA4ABB8) : const Color(0xFF667085);
    final textHint =
        isDark ? const Color(0xFF747B8B) : const Color(0xFF98A2B3);
    final accent = const Color(0xFF1F5FE8);
    final accentSoft =
        isDark ? const Color(0xFF1A2E58) : const Color(0xFFE6EEFC);

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(
              cardBg: cardBg,
              cardBorder: cardBorder,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              textHint: textHint,
              accent: accent,
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SafeMap(
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _selectedPoint,
                          initialZoom: 16.0,
                          onTap: (_, LatLng point) => _onMapTap(point),
                          onPositionChanged: _onMapDrag,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: isDark
                                ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                                : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            subdomains: isDark
                                ? const ['a', 'b', 'c', 'd']
                                : const [],
                            userAgentPackageName: 'com.lyncspace.grozfygo',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _selectedPoint,
                                width: 56,
                                height: 56,
                                child: Icon(
                                  Icons.location_pin,
                                  size: 48,
                                  color: accent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_loading)
                    Container(
                      color: Colors.black.withValues(alpha: 0.25),
                      child: const Center(child: _LocationPickerLoading()),
                    ),
                  if (_searchResults.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 16,
                      right: 16,
                      child: _SearchResultsDropdown(
                        cardBg: cardBg,
                        cardBorder: cardBorder,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                        accent: accent,
                        results: _searchResults,
                        onSelect: _selectSearchResult,
                      ),
                    ),
                  Positioned(
                    left: 16,
                    bottom: 16,
                    child: _UseMyLocationPill(
                      onTap: (_loading || _saving)
                          ? null
                          : _loadCurrentLocation,
                      cardBg: cardBg,
                      accent: accent,
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: _MapControls(
                      cardBg: cardBg,
                      accent: accent,
                      cardBorder: cardBorder,
                      onLocate:
                          (_loading || _saving) ? null : _loadCurrentLocation,
                      onZoomIn: () {
                        final z = _mapController.camera.zoom + 1;
                        _mapController.move(
                          _mapController.camera.center,
                          z.clamp(2.0, 19.0),
                        );
                      },
                      onZoomOut: () {
                        final z = _mapController.camera.zoom - 1;
                        _mapController.move(
                          _mapController.camera.center,
                          z.clamp(2.0, 19.0),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            _buildBottomSection(
              cardBg: cardBg,
              cardBorder: cardBorder,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              accent: accent,
              accentSoft: accentSoft,
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader({
    required Color cardBg,
    required Color cardBorder,
    required Color textPrimary,
    required Color textSecondary,
    required Color textHint,
    required Color accent,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _BackChip(
                onTap: () => Navigator.of(context).maybePop(),
                cardBg: cardBg,
                cardBorder: cardBorder,
                textPrimary: textPrimary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Select Delivery Zone',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Choose your preferred delivery area',
                      style: TextStyle(
                        fontSize: 13,
                        color: textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: textSecondary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    cursorColor: accent,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'Search area or location...',
                      hintStyle: TextStyle(
                        color: textHint,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                if (_searching)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                else if (_searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: _clearSearch,
                    child: Icon(
                      Icons.close_rounded,
                      color: textSecondary,
                      size: 20,
                    ),
                  )
                else
                  Icon(
                    Icons.tune_rounded,
                    color: textSecondary,
                    size: 22,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSection({
    required Color cardBg,
    required Color cardBorder,
    required Color textPrimary,
    required Color textSecondary,
    required Color accent,
    required Color accentSoft,
    required bool isDark,
  }) {
    final bool disableConfirm = _loading || _saving || _error != null;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3D4255)
                      : const Color(0xFFD0D5DD),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Selected Delivery Zone',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accentSoft,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.location_on_rounded,
                      color: accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Selected Location',
                          style: TextStyle(
                            fontSize: 12,
                            color: textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _addressLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: textPrimary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _clearSearch,
                    child: Row(
                      children: [
                        Icon(Icons.edit_rounded, color: accent, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Edit',
                          style: TextStyle(
                            color: accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              _ErrorBanner(
                message: _error!,
                onTurnOnGps: () async {
                  await Geolocator.openLocationSettings();
                },
                onRetry: _loadCurrentLocation,
              )
            else
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF14352A)
                      : const Color(0xFFE7F7EE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      color: Color(0xFF118A52),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You can change your delivery zone anytime.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark
                              ? const Color(0xFF8FD2A8)
                              : const Color(0xFF118A52),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: disableConfirm ? null : _confirmSelection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  disabledBackgroundColor: accent.withValues(alpha: 0.4),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.check_circle_rounded, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Confirm Location',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackChip extends StatelessWidget {
  const _BackChip({
    required this.onTap,
    required this.cardBg,
    required this.cardBorder,
    required this.textPrimary,
  });
  final VoidCallback onTap;
  final Color cardBg;
  final Color cardBorder;
  final Color textPrimary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(Icons.arrow_back_rounded, size: 22, color: textPrimary),
        ),
      ),
    );
  }
}

class _UseMyLocationPill extends StatelessWidget {
  const _UseMyLocationPill({
    required this.onTap,
    required this.cardBg,
    required this.accent,
  });

  final VoidCallback? onTap;
  final Color cardBg;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(99),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.near_me_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'Use my location',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.cardBg,
    required this.accent,
    required this.cardBorder,
    required this.onLocate,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final Color cardBg;
  final Color accent;
  final Color cardBorder;
  final VoidCallback? onLocate;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _MapControlButton(
          icon: Icons.gps_fixed_rounded,
          color: accent,
          onTap: onLocate,
          cardBg: cardBg,
        ),
        const SizedBox(height: 10),
        Container(
          width: 44,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onZoomIn,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.add_rounded, color: accent, size: 22),
                ),
              ),
              Container(height: 1, color: cardBorder),
              InkWell(
                onTap: onZoomOut,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.remove_rounded, color: accent, size: 22),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.cardBg,
  });
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final Color cardBg;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

class _SearchResultsDropdown extends StatelessWidget {
  const _SearchResultsDropdown({
    required this.cardBg,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.results,
    required this.onSelect,
  });

  final Color cardBg;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final List<SearchResult> results;
  final void Function(SearchResult) onSelect;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: results.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: cardBorder, thickness: 1),
          itemBuilder: (context, index) {
            final r = results[index];
            return ListTile(
              dense: true,
              leading: Icon(Icons.location_on_outlined, color: accent),
              title: Text(
                r.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => onSelect(r),
            );
          },
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onTurnOnGps,
    required this.onRetry,
  });
  final String message;
  final VoidCallback onTurnOnGps;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDA29B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.location_off_rounded,
                color: Color(0xFFB42318),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFFB42318),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onTurnOnGps,
                  icon: const Icon(Icons.gps_fixed_rounded, size: 16),
                  label: const Text('Turn On GPS'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB42318),
                    side: const BorderSide(color: Color(0xFFFDA29B)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB42318),
                    side: const BorderSide(color: Color(0xFFFDA29B)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class _LocationPickerLoading extends StatelessWidget {
  const _LocationPickerLoading();

  @override
  Widget build(BuildContext context) {
    return FrostCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.mango.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                )
                    .animate(onPlay: (controller) => controller.repeat())
                    .shimmer(
                      duration: 1000.ms,
                      color: AppTheme.mango.withValues(alpha: 0.3),
                    ),
                const Icon(
                  Icons.my_location_rounded,
                  color: AppTheme.mango,
                  size: 20,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Loading location...',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
