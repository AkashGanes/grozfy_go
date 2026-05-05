import 'dart:io';

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

  bool _foregroundPermanentlyDenied = false;
  bool _backgroundPermanentlyDenied = false;
  bool _notificationPermanentlyDenied = false;

  bool _foregroundRequesting = false;
  bool _backgroundRequesting = false;
  bool _notificationRequesting = false;

  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check when user returns from system settings
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAll();
    }
  }

  Future<void> _checkAll() async {
    setState(() => _checking = true);

    final LocationPermission locPerm = await Geolocator.checkPermission();
    final PermissionStatus notifStatus = await Permission.notification.status;

    if (!mounted) return;

    final bool foreground = locPerm == LocationPermission.whileInUse ||
        locPerm == LocationPermission.always;
    final bool background = locPerm == LocationPermission.always;
    final bool locForeverDenied = locPerm == LocationPermission.deniedForever;

    // On Android 11+, upgrading from whileInUse → always requires the user
    // to go to settings manually; treat it as "open settings needed".
    final bool backgroundNeedsSettings = Platform.isAndroid &&
        locPerm == LocationPermission.whileInUse;

    setState(() {
      _foregroundGranted = foreground;
      _backgroundGranted = background;
      _notificationGranted = notifStatus.isGranted;

      _foregroundPermanentlyDenied = locForeverDenied;
      _backgroundPermanentlyDenied = locForeverDenied || backgroundNeedsSettings;
      _notificationPermanentlyDenied = notifStatus.isPermanentlyDenied;

      _checking = false;
    });

    // Keep AppController state in sync with real OS state
    if (mounted) {
      AppScope.of(context).setPermissionState(
        foreground: foreground,
        background: background,
        notification: notifStatus.isGranted,
      );
    }
  }

  Future<void> _requestForeground() async {
    setState(() => _foregroundRequesting = true);

    LocationPermission perm = await Geolocator.checkPermission();

    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (!mounted) return;

    if (perm == LocationPermission.deniedForever) {
      // Permanently denied — send to system settings
      await Geolocator.openAppSettings();
    }

    setState(() => _foregroundRequesting = false);
    await _checkAll();
  }

  Future<void> _requestBackground() async {
    if (!_foregroundGranted) {
      showInfoSnack(context, 'Allow foreground location first');
      return;
    }

    setState(() => _backgroundRequesting = true);

    final LocationPermission perm = await Geolocator.checkPermission();

    if (perm == LocationPermission.always) {
      // Already granted
      setState(() => _backgroundRequesting = false);
      await _checkAll();
      return;
    }

    if (perm == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    } else if (perm == LocationPermission.whileInUse) {
      // On Android 11+ the OS may not show a dialog for "always"; it redirects
      // to settings. We request and fall back to settings if still not granted.
      final LocationPermission result = await Geolocator.requestPermission();
      if (mounted && result != LocationPermission.always) {
        await Geolocator.openAppSettings();
      }
    }

    if (!mounted) return;
    setState(() => _backgroundRequesting = false);
    await _checkAll();
  }

  Future<void> _requestNotification() async {
    setState(() => _notificationRequesting = true);

    final PermissionStatus status = await Permission.notification.request();

    if (!mounted) return;

    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }

    setState(() => _notificationRequesting = false);
    await _checkAll();
  }

  @override
  Widget build(BuildContext context) {
    final bool allGranted =
        _foregroundGranted && _backgroundGranted && _notificationGranted;

    return AppShell(
      title: 'Permission Setup',
      subtitle: 'Location + notifications are mandatory for order matching',
      child: _checking
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FrostCard(
                  child: Text(
                    'To receive nearby orders, keep GPS enabled in both '
                    'foreground and background. Notification access is required '
                    'for instant order alerts.',
                  ),
                ),
                const SizedBox(height: 12),
                FrostCard(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  child: Column(
                    children: [
                      _PermissionRow(
                        icon: Icons.location_on_rounded,
                        title: 'Foreground location',
                        subtitle: 'GPS access while the app is open',
                        granted: _foregroundGranted,
                        permanentlyDenied: _foregroundPermanentlyDenied,
                        loading: _foregroundRequesting,
                        onTap: _foregroundGranted
                            ? null
                            : _foregroundPermanentlyDenied
                                ? Geolocator.openAppSettings
                                : _requestForeground,
                      ),
                      const Divider(height: 1),
                      _PermissionRow(
                        icon: Icons.location_searching_rounded,
                        title: 'Background location',
                        subtitle: 'GPS access while the app is minimised',
                        granted: _backgroundGranted,
                        permanentlyDenied: _backgroundPermanentlyDenied,
                        loading: _backgroundRequesting,
                        onTap: _backgroundGranted
                            ? null
                            : _backgroundPermanentlyDenied
                                ? Geolocator.openAppSettings
                                : _requestBackground,
                      ),
                      const Divider(height: 1),
                      _PermissionRow(
                        icon: Icons.notifications_rounded,
                        title: 'Notifications',
                        subtitle: 'Instant alerts for incoming orders',
                        granted: _notificationGranted,
                        permanentlyDenied: _notificationPermanentlyDenied,
                        loading: _notificationRequesting,
                        onTap: _notificationGranted
                            ? null
                            : _notificationPermanentlyDenied
                                ? openAppSettings
                                : _requestNotification,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: allGranted
                      ? () => Navigator.of(context).pushNamed(AppRoutes.tracking)
                      : null,
                  child: const Text('Continue to Tracking Setup'),
                ),
              ],
            ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.permanentlyDenied,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final bool permanentlyDenied;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = granted
        ? const Color(0xFF4CAF50)
        : permanentlyDenied
            ? Colors.red
            : Colors.orange;

    final String actionLabel = granted
        ? 'Granted'
        : permanentlyDenied
            ? 'Open Settings'
            : 'Allow';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Icon(icon, color: accent, size: 26),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : granted
              ? Icon(Icons.check_circle_rounded, color: accent, size: 22)
              : TextButton(
                  onPressed: onTap,
                  style: TextButton.styleFrom(foregroundColor: accent),
                  child: Text(
                    actionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
    );
  }
}
