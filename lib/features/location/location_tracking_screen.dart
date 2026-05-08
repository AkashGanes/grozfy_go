import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';

class LocationTrackingScreen extends StatefulWidget {
  const LocationTrackingScreen({super.key});

  @override
  State<LocationTrackingScreen> createState() => _LocationTrackingScreenState();
}

class _LocationTrackingScreenState extends State<LocationTrackingScreen> {
  final MapController _mapController = MapController();
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer(AppController app) {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: app.trackingInterval),
      (_) => app.tickLocation(),
    );
  }

  LatLng _currentLatLng(AppController app) {
    final lat = app.currentLatitude;
    final lng = app.currentLongitude;
    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }
    return const LatLng(11.1271, 78.6569);
  }

  void _centerMap(AppController app) {
    try {
      _mapController.move(_currentLatLng(app), 16.0);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final position = _currentLatLng(app);

    return AppShell(
      title: 'Live Location Tracking',
      subtitle: 'Send GPS to backend every few seconds',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.map_rounded),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Live GPS Position',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (app.isTracking)
                      IconButton(
                        icon: Icon(
                          Icons.my_location_rounded,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        onPressed: () => _centerMap(app),
                        tooltip: 'Center on position',
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 200,
                    child: app.isTracking
                        ? SafeMap(child: FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: position,
                              initialZoom: 16.0,
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.all &
                                    ~InteractiveFlag.rotate,
                              ),
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
                                    point: position,
                                    width: 40,
                                    height: 40,
                                    child: Icon(
                                      Icons.navigation_rounded,
                                      color: Theme.of(context).colorScheme.primary,
                                      size: 32,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ))
                        : Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFE6F2FF),
                                  Color(0xFFDDF7EE),
                                ],
                              ),
                            ),
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.location_off_rounded,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Start tracking to see live map',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      app.isTracking
                          ? Icons.gps_fixed_rounded
                          : Icons.gps_off_rounded,
                      size: 16,
                      color: app.isTracking ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Coordinates: ${app.liveCoordinates}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Update interval: ${app.trackingInterval}s'),
                Slider(
                  min: 5,
                  max: 30,
                  divisions: 5,
                  value: app.trackingInterval.toDouble(),
                  label: '${app.trackingInterval}s',
                  onChanged: (double value) {
                    app.setTrackingInterval(value.toInt());
                    if (app.isTracking) {
                      _startTimer(app);
                    }
                  },
                ),
                if (app.isTracking)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.battery_alert_rounded,
                          size: 16,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          app.trackingInterval <= 10
                              ? 'High accuracy — higher battery usage'
                              : 'Balanced accuracy and battery usage',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final scaffoldMessenger = ScaffoldMessenger.of(
                            context,
                          );
                          if (app.isTracking) {
                            app.stopTracking();
                            _timer?.cancel();
                            scaffoldMessenger.showSnackBar(
                              const SnackBar(content: Text('Tracking stopped')),
                            );
                          } else {
                            final String? error = await app.startTracking();
                            if (error != null) {
                              scaffoldMessenger.showSnackBar(
                                SnackBar(content: Text(error)),
                              );
                              return;
                            }
                            _startTimer(app);
                            scaffoldMessenger.showSnackBar(
                              const SnackBar(
                                content: Text('Live tracking started'),
                              ),
                            );
                            // Center map on current position after tracking starts
                            Future.delayed(
                              const Duration(milliseconds: 500),
                              () {
                                if (mounted) _centerMap(app);
                              },
                            );
                          }
                        },
                        icon: Icon(
                          app.isTracking
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        label: Text(
                          app.isTracking ? 'Stop Tracking' : 'Start Tracking',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
            },
            child: const Text('Finish Setup and Go to Dashboard'),
          ),
        ],
      ),
    );
  }
}
