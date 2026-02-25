import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';

class CurrentLocationPickerScreen extends StatefulWidget {
  const CurrentLocationPickerScreen({super.key});

  @override
  State<CurrentLocationPickerScreen> createState() =>
      _CurrentLocationPickerScreenState();
}

class _CurrentLocationPickerScreenState
    extends State<CurrentLocationPickerScreen> {
  final MapController _mapController = MapController();

  LatLng _selectedPoint = const LatLng(28.6139, 77.2090);
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = AppScope.of(context);
      if (app.hasSelectedLocation &&
          app.currentLatitude != null &&
          app.currentLongitude != null) {
        _selectedPoint = LatLng(app.currentLatitude!, app.currentLongitude!);
        _loading = false;
        _moveMapToSelected();
        setState(() {});
      } else {
        _loadCurrentLocation();
      }
    });
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
        });
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _loading = false;
          _error =
              'Location permission permanently denied. Open settings to enable it.';
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
      });
      _moveMapToSelected();
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'Unable to fetch current location. Try again.';
      });
    }
  }

  Future<void> _confirmSelection() async {
    final app = AppScope.of(context);
    setState(() => _saving = true);

    await app.setSelectedLocation(
      latitude: _selectedPoint.latitude,
      longitude: _selectedPoint.longitude,
      label:
          '${_selectedPoint.latitude.toStringAsFixed(5)}, ${_selectedPoint.longitude.toStringAsFixed(5)}',
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

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Select Current Location',
      subtitle: 'Pick your live location to start receiving nearby orders',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tap on map to fine-tune your exact delivery zone.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 320,
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: _selectedPoint,
                              initialZoom: 16.0,
                              onTap: (_, LatLng point) {
                                setState(() => _selectedPoint = point);
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName:
                                    'com.example.delivery_partner_app',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _selectedPoint,
                                    width: 56,
                                    height: 56,
                                    child: const Icon(
                                      Icons.location_pin,
                                      size: 44,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Selected: ${_selectedPoint.latitude.toStringAsFixed(5)}, ${_selectedPoint.longitude.toStringAsFixed(5)}',
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            FrostCard(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _loadCurrentLocation,
                  icon: const Icon(Icons.my_location_rounded),
                  label: const Text('Use Current GPS'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          await Geolocator.openAppSettings();
                        },
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('Open Settings'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: (_loading || _saving) ? null : _confirmSelection,
            child: Text(_saving ? 'Saving location...' : 'Confirm Location'),
          ),
        ],
      ),
    );
  }
}
