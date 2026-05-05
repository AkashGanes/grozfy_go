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
        title: app.t('navigation'),
        subtitle: app.t('no_active_route'),
        child: ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard),
          child: Text(app.t('back_to_dashboard')),
        ),
      );
    }

    return AppShell(
      title: app.t('navigation'),
      subtitle: app.t('route_summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.route_rounded, color: Colors.deepOrange),
                    const SizedBox(width: 8),
                    Text(
                      app.t('delivery_route'),
                      style: const TextStyle(
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
                  title: app.t('pickup_store'),
                  subtitle: order.pickup,
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 12),
                _StepTile(
                  icon: Icons.location_on_rounded,
                  iconColor: Colors.red,
                  title: app.t('delivery_drop'),
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
            label: Text(app.t('open_google_maps')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DeliveryTrackingScreen(
                    deliveryName: order.orderId,
                    customerName: order.customerName,
                    storeName: order.storeName,
                    contactNumber: order.customerPhone.isNotEmpty
                        ? order.customerPhone
                        : order.contactNumber,
                    dropAddress: order.deliveryAddress,
                    dropLat: order.latitude,
                    dropLng: order.longitude,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.map_rounded),
            label: Text(app.t('use_inapp_nav')),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () async {
              final error = await app.updateOrderStatus(
                OrderProgressStatus.reachedPickup,
              );
              if (!context.mounted) return;
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(error)),
                );
                return;
              }
              Navigator.of(context).pushNamed(AppRoutes.orderStatus);
            },
            child: Text(app.t('reached_pickup')),
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
    // Try each URI in order, launching without canLaunchUrl check because
    // custom schemes (google.navigation, comgooglemaps) can return false on
    // Android 11+ even when the app is installed.
    if (Platform.isAndroid) {
      // Native navigation intent — starts turn-by-turn from current GPS location.
      final Uri navUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
      try {
        if (await launchUrl(navUri, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {}

      // Fallback: geo URI with destination query (opens Maps or lets user choose).
      final Uri geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
      try {
        if (await launchUrl(geoUri, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {}
    }

    if (Platform.isIOS) {
      final Uri googleMapsIos = Uri.parse(
        'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving',
      );
      try {
        if (await launchUrl(googleMapsIos)) return;
      } catch (_) {}

      final Uri appleMaps = Uri.parse('maps:?daddr=$lat,$lng');
      try {
        if (await launchUrl(appleMaps)) return;
      } catch (_) {}
    }

    // Universal fallback: web Google Maps with driving directions.
    final Uri webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=$lat,$lng'
      '&travelmode=driving',
    );
    try {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return;
    } catch (_) {}

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps')),
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
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
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                  height: 1.3,
                ),
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.12)),
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
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withValues(alpha: 0.6),
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.onSurface.withValues(alpha: 0.4)),
        const SizedBox(width: 8),
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.6),
              fontSize: 12,
            ),
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
