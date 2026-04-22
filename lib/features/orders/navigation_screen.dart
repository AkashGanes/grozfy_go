import 'dart:io';

import 'package:flutter/material.dart';
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

    return AppShell(
      title: 'Navigation',
      subtitle: 'Route summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.route_rounded, color: Colors.deepOrange),
                    SizedBox(width: 8),
                    Text(
                      'Delivery Route',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _StepTile(
                  icon: Icons.store_rounded,
                  iconColor: Colors.blue,
                  title: 'Pickup store',
                  subtitle: order.pickup,
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: Icon(Icons.arrow_downward_rounded, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                _StepTile(
                  icon: Icons.location_on_rounded,
                  iconColor: Colors.red,
                  title: 'Delivery drop',
                  subtitle: order.drop.isNotEmpty
                      ? order.drop
                      : order.deliveryAddress,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _StatChip(
                        icon: Icons.straighten_rounded,
                        label: 'Distance',
                        value: '${order.distanceKm.toStringAsFixed(1)} km',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatChip(
                        icon: Icons.sell_rounded,
                        label: 'Earnings',
                        value:
                            'Rs. ${order.estimatedEarnings.toStringAsFixed(0)}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoLine(
                  icon: Icons.pin_drop_rounded,
                  label: 'Coordinates',
                  value:
                      '${order.latitude.toStringAsFixed(5)}, ${order.longitude.toStringAsFixed(5)}',
                ),
                const SizedBox(height: 8),
                _InfoLine(
                  icon: Icons.receipt_long_rounded,
                  label: 'Order',
                  value: order.orderId,
                ),
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
    final Uri nativeUri = Platform.isAndroid
        ? Uri.parse(
            'https://www.google.com/maps/dir/?api=1'
            '&destination=$lat,$lng'
            '&travelmode=driving',
          )
        : Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=driving');

    if (await canLaunchUrl(nativeUri)) {
      await launchUrl(nativeUri);
      return;
    }

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
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.black54, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.deepOrange),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
