import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';

class DeliveryLocationPickerScreen extends StatefulWidget {
  const DeliveryLocationPickerScreen({super.key});

  @override
  State<DeliveryLocationPickerScreen> createState() =>
      _DeliveryLocationPickerScreenState();
}

class _DeliveryLocationPickerScreenState
    extends State<DeliveryLocationPickerScreen>
    with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  LatLng _selectedPoint = const LatLng(28.6139, 77.2090);
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _isUpdatingFromText = false;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen(
      (ServiceStatus status) {
        if (!mounted) return;
        if (status == ServiceStatus.enabled) {
          if (_error != null) _loadCurrentLocation();
        } else {
          setState(() => _error = 'Location service is disabled. Please enable GPS.');
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = AppScope.of(context);
      if (app.hasSelectedLocation &&
          app.currentLatitude != null &&
          app.currentLongitude != null) {
        _selectedPoint = LatLng(app.currentLatitude!, app.currentLongitude!);
        _latController.text = _selectedPoint.latitude.toStringAsFixed(6);
        _lngController.text = _selectedPoint.longitude.toStringAsFixed(6);
        _loading = false;
        _moveMapToSelected();
        setState(() {});
      } else {
        _loadCurrentLocation();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceStatusSubscription?.cancel();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _error != null) {
      _loadCurrentLocation();
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
        _latController.text = _selectedPoint.latitude.toStringAsFixed(6);
        _lngController.text = _selectedPoint.longitude.toStringAsFixed(6);
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

  void _updateLocationFromText() {
    if (_isUpdatingFromText) return;

    final double? lat = double.tryParse(_latController.text);
    final double? lng = double.tryParse(_lngController.text);

    if (lat == null || lng == null) {
      setState(() => _error = 'Invalid coordinates format');
      return;
    }

    if (lat < -90 || lat > 90) {
      setState(() => _error = 'Latitude must be between -90 and 90');
      return;
    }

    if (lng < -180 || lng > 180) {
      setState(() => _error = 'Longitude must be between -180 and 180');
      return;
    }

    setState(() {
      _selectedPoint = LatLng(lat, lng);
      _error = null;
    });
    _moveMapToSelected();
  }

  void _onMapTap(LatLng point) {
    _isUpdatingFromText = true;
    setState(() {
      _selectedPoint = point;
      _latController.text = point.latitude.toStringAsFixed(6);
      _lngController.text = point.longitude.toStringAsFixed(6);
      _error = null;
    });
    _isUpdatingFromText = false;
  }

  void _moveMapToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      try {
        _mapController.move(_selectedPoint, 16.0);
      } catch (_) {}
    });
  }

  Future<void> _confirmSelection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

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

    Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Select Delivery Location',
      subtitle: 'Pick location by pin or enter coordinates manually',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tap on map to place pin OR enter coordinates below',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 250,
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: _selectedPoint,
                              initialZoom: 16.0,
                              onTap: (tapPosition, point) => _onMapTap(point),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName:
                                    'com.lyncspace.grozfy_go',
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
              ],
            ),
          ),
          const SizedBox(height: 12),
          FrostCard(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Manual Coordinates Entry',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _latController,
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                            hintText: '-90 to 90',
                            prefixIcon: Icon(Icons.north),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^-?\d*\.?\d*'),
                            ),
                          ],
                          onChanged: (_) => _updateLocationFromText(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Required';
                            }
                            final lat = double.tryParse(value);
                            if (lat == null) {
                              return 'Invalid';
                            }
                            if (lat < -90 || lat > 90) {
                              return '-90 to 90';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _lngController,
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                            hintText: '-180 to 180',
                            prefixIcon: Icon(Icons.east),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^-?\d*\.?\d*'),
                            ),
                          ],
                          onChanged: (_) => _updateLocationFromText(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Required';
                            }
                            final lng = double.tryParse(value);
                            if (lng == null) {
                              return 'Invalid';
                            }
                            if (lng < -180 || lng > 180) {
                              return '-180 to 180';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Selected: ${_selectedPoint.latitude.toStringAsFixed(6)}, ${_selectedPoint.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            FrostCard(
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _loadCurrentLocation,
                  icon: const Icon(Icons.my_location_rounded),
                  label: const Text('Use GPS'),
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
                  label: const Text('Settings'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: (_loading || _saving) ? null : _confirmSelection,
            child: Text(_saving ? 'Saving...' : 'Confirm Location'),
          ),
        ],
      ),
    );
  }
}
