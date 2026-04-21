import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';
import 'delivery_tracking_screen.dart';

class NavigationScreen extends StatelessWidget {
  const NavigationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final order = app.activeOrder;

    if (order == null) {
      return AppShell(
        title: 'Navigation',
        subtitle: 'No active route',
        child: ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard),
          child: const Text('Back to Dashboard'),
        ),
      );
    }

    final dropPoint = LatLng(order.latitude, order.longitude);

    return AppShell(
      title: 'Navigation',
      subtitle: 'Route to delivery location',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 220,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: dropPoint,
                        initialZoom: 14.0,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.lyncspace.grozfy_go',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: dropPoint,
                              width: 44,
                              height: 44,
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.red,
                                size: 40,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _row('Pickup', order.pickup),
                _row('Drop', order.drop),
                _row(
                  'Coordinates',
                  '${order.latitude.toStringAsFixed(5)}, ${order.longitude.toStringAsFixed(5)}',
                ),
                _row('Distance', '${order.distanceKm.toStringAsFixed(1)} km'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _launchGoogleMapsNavigation(
              context,
              order.latitude,
              order.longitude,
            ),
            icon: const Icon(Icons.navigation_rounded),
            label: const Text('Open in Google Maps'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DeliveryTrackingScreen(),
                ),
              );
            },
            icon: const Icon(Icons.map_rounded),
            label: const Text('Use In-app Navigation'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              app.updateOrderStatus(OrderProgressStatus.reachedPickup);
              Navigator.of(context).pushNamed(AppRoutes.orderStatus);
            },
            child: const Text('Reached Pickup'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchGoogleMapsNavigation(
    BuildContext context,
    double lat,
    double lng,
  ) async {
    // Native Google Maps turn-by-turn navigation
    final Uri nativeUri = Platform.isAndroid
        ? Uri.parse('google.navigation:q=$lat,$lng&mode=d')
        : Uri.parse(
            'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving',
          );

    if (await canLaunchUrl(nativeUri)) {
      await launchUrl(nativeUri);
      return;
    }

    // Fallback: open in browser / OS map handler
    final Uri webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=$lat,$lng'
      '&travelmode=driving',
    );

    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps')),
      );
    }
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
