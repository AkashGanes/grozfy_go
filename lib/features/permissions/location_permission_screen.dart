import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';

class LocationPermissionScreen extends StatelessWidget {
  const LocationPermissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return AppShell(
      title: 'Permission Setup',
      subtitle: 'Location + notifications are mandatory for order matching',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FrostCard(
            child: Text(
              'To receive nearby orders, keep GPS enabled in both foreground '
              'and background. Notification access is required for instant '
              'order alerts.',
            ),
          ),
          const SizedBox(height: 12),
          FrostCard(
            child: Column(
              children: [
                SwitchListTile(
                  value: app.permissionState.foregroundLocation,
                  onChanged: (bool value) =>
                      app.setPermissionState(foreground: value),
                  title: const Text('Foreground location'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: app.permissionState.backgroundLocation,
                  onChanged: (bool value) =>
                      app.setPermissionState(background: value),
                  title: const Text('Background location'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: app.permissionState.notification,
                  onChanged: (bool value) =>
                      app.setPermissionState(notification: value),
                  title: const Text('Notification permission'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              showInfoSnack(
                context,
                'If permission is blocked, open system settings to enable it.',
              );
            },
            icon: const Icon(Icons.settings_rounded),
            label: const Text('Open App Settings Guide'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              if (!app.permissionState.allGranted) {
                showInfoSnack(context, 'Grant all permissions to continue');
                return;
              }
              Navigator.of(context).pushNamed(AppRoutes.tracking);
            },
            child: const Text('Continue to Tracking Setup'),
          ),
        ],
      ),
    );
  }
}
