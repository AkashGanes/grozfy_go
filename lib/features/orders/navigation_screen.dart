import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';

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
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFDDEBFF), Color(0xFFEAFBEF)],
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.route_rounded, size: 52),
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
              showInfoSnack(context, 'In-app navigation enabled');
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
