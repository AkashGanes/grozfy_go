import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';

class LocationTrackingScreen extends StatefulWidget {
  const LocationTrackingScreen({super.key});

  @override
  State<LocationTrackingScreen> createState() => _LocationTrackingScreenState();
}

class _LocationTrackingScreenState extends State<LocationTrackingScreen> {
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

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

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
                const Row(
                  children: [
                    Icon(Icons.map_rounded),
                    SizedBox(width: 8),
                    Text(
                      'Google Maps SDK placeholder',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 170,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE6F2FF), Color(0xFFDDF7EE)],
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.location_pin, size: 48),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Current coordinates: ${app.liveCoordinates}'),
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
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (app.isTracking) {
                            app.stopTracking();
                            _timer?.cancel();
                            showInfoSnack(context, 'Tracking stopped');
                          } else {
                            final String? error = app.startTracking();
                            if (error != null) {
                              showInfoSnack(context, error);
                              return;
                            }
                            _startTimer(app);
                            showInfoSnack(context, 'Live tracking started');
                          }
                        },
                        child: Text(
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
