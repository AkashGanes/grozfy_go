import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';

class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  State<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen>
    with WidgetsBindingObserver {
  bool _foregroundGranted = false;
  bool _backgroundGranted = false;
  bool _notificationGranted = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllPermissions();
    }
  }

  Future<void> _checkAllPermissions() async {
    final locationPerm = await Geolocator.checkPermission();
    final notifStatus = await Permission.notification.status;

    if (!mounted) return;

    setState(() {
      _foregroundGranted = locationPerm == LocationPermission.whileInUse ||
          locationPerm == LocationPermission.always;
      _backgroundGranted = locationPerm == LocationPermission.always;
      _notificationGranted = notifStatus.isGranted;
      _checking = false;
    });

    final app = AppScope.of(context);
    app.setPermissionState(
      foreground: _foregroundGranted,
      background: _backgroundGranted,
      notification: _notificationGranted,
    );
  }

  Future<void> _requestForegroundLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      _showSettingsDialog(
        'Location permission is permanently denied. Please enable it in app settings.',
      );
      return;
    }

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    await _checkAllPermissions();
  }

  Future<void> _requestBackgroundLocation() async {
    if (!_foregroundGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please grant foreground location first'),
        ),
      );
      return;
    }

    final status = await Permission.locationAlways.status;

    if (status.isPermanentlyDenied) {
      if (!mounted) return;
      _showSettingsDialog(
        'Background location is permanently denied. Please enable "Allow all the time" in app settings.',
      );
      return;
    }

    if (!status.isGranted) {
      await Permission.locationAlways.request();
    }

    await _checkAllPermissions();
  }

  Future<void> _requestNotification() async {
    final status = await Permission.notification.status;

    if (status.isPermanentlyDenied) {
      if (!mounted) return;
      _showSettingsDialog(
        'Notification permission is permanently denied. Please enable it in app settings.',
      );
      return;
    }

    if (!status.isGranted) {
      await Permission.notification.request();
    }

    await _checkAllPermissions();
  }

  void _showSettingsDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permission Required'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  bool get _allGranted =>
      _foregroundGranted && _backgroundGranted && _notificationGranted;

  @override
  Widget build(BuildContext context) {
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
          if (_checking)
            const FrostCard(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else
            FrostCard(
              child: Column(
                children: [
                  _PermissionTile(
                    title: 'Foreground Location',
                    subtitle: _foregroundGranted
                        ? 'Granted'
                        : 'Tap to allow location while using the app',
                    icon: Icons.location_on_rounded,
                    granted: _foregroundGranted,
                    onTap: _foregroundGranted ? null : _requestForegroundLocation,
                  ),
                  const Divider(height: 1),
                  _PermissionTile(
                    title: 'Background Location',
                    subtitle: _backgroundGranted
                        ? 'Granted (Always)'
                        : !_foregroundGranted
                            ? 'Grant foreground location first'
                            : 'Tap to allow location all the time',
                    icon: Icons.location_searching_rounded,
                    granted: _backgroundGranted,
                    onTap: _backgroundGranted ? null : _requestBackgroundLocation,
                  ),
                  const Divider(height: 1),
                  _PermissionTile(
                    title: 'Notifications',
                    subtitle: _notificationGranted
                        ? 'Granted'
                        : 'Tap to allow order alerts',
                    icon: Icons.notifications_rounded,
                    granted: _notificationGranted,
                    onTap: _notificationGranted ? null : _requestNotification,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => openAppSettings(),
            icon: const Icon(Icons.settings_rounded),
            label: const Text('Open App Settings'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _allGranted
                ? () {
                    Navigator.of(context).pushNamed(AppRoutes.tracking);
                  }
                : null,
            child: const Text('Continue to Tracking Setup'),
          ),
          if (!_allGranted) ...[
            const SizedBox(height: 8),
            const Text(
              'All permissions must be granted to continue',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.red,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool granted;
  final VoidCallback? onTap;

  const _PermissionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.granted,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: granted ? Colors.green : Theme.of(context).colorScheme.onSurface,
      ),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: granted ? Colors.green : Colors.grey[600],
        ),
      ),
      trailing: granted
          ? const Icon(Icons.check_circle_rounded, color: Colors.green)
          : const Icon(Icons.arrow_forward_ios_rounded, size: 16),
      onTap: onTap,
    );
  }
}
