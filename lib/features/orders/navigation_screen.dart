import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
      subtitle: 'Route guidance and ETA tracking',
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
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.red,
                                size: 36,
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
                _row('ETA', '18 mins'),
                _row('Distance', '${order.distanceKm.toStringAsFixed(1)} km'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              showInfoSnack(context, 'Launching Google Maps route');
            },
            icon: const Icon(Icons.open_in_new_rounded),
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

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
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
