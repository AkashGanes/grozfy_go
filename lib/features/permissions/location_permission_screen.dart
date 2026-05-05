import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/services/fcm_service.dart';
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
  bool _callGranted = false;

  bool _foregroundPermanentlyDenied = false;
  bool _backgroundPermanentlyDenied = false;
  bool _notificationPermanentlyDenied = false;
  bool _callPermanentlyDenied = false;

  bool _foregroundRequesting = false;
  bool _backgroundRequesting = false;
  bool _notificationRequesting = false;
  bool _callRequesting = false;

  bool _initialized = false;

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

  // Same pattern as CurrentLocationPickerScreen — re-check on every resume,
  // no flag needed. The surface-destroyed logs in flutter run are the debug
  // runner losing its socket when the activity goes to background; the app
  // itself stays alive and resumes correctly.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAll();
    }
  }

  Future<void> _checkAll() async {
    final results = await Future.wait([
      Geolocator.checkPermission(),
      Permission.notification.status,
      Permission.phone.status,
    ]);

    if (!mounted) return;

    final LocationPermission locPerm = results[0] as LocationPermission;
    final PermissionStatus notifStatus = results[1] as PermissionStatus;
    final PermissionStatus callStatus = results[2] as PermissionStatus;

    final bool foreground = locPerm == LocationPermission.whileInUse ||
        locPerm == LocationPermission.always;
    final bool background = locPerm == LocationPermission.always;
    final bool locForeverDenied = locPerm == LocationPermission.deniedForever;

    setState(() {
      _foregroundGranted = foreground;
      _backgroundGranted = background;
      _notificationGranted = notifStatus.isGranted;
      _callGranted = callStatus.isGranted;
      _foregroundPermanentlyDenied = locForeverDenied;
      // Only mark background as permanently denied when location is fully
      // blocked. The whileInUse case is handled by an in-app request first,
      // so it shows "Allow" not "Open Settings".
      _backgroundPermanentlyDenied = locForeverDenied;
      _notificationPermanentlyDenied = notifStatus.isPermanentlyDenied;
      _callPermanentlyDenied = callStatus.isPermanentlyDenied;
      _initialized = true;
      // Clear any stuck requesting spinners
      _foregroundRequesting = false;
      _backgroundRequesting = false;
      _notificationRequesting = false;
      _callRequesting = false;
    });

    if (!mounted) return;
    AppScope.of(context).setPermissionState(
      foreground: foreground,
      background: background,
      notification: notifStatus.isGranted,
      phoneCall: callStatus.isGranted,
    );
  }

  // Shows guidance then opens app settings.
  // Uses await like CurrentLocationPickerScreen does for openLocationSettings.
  Future<void> _goToSettings(
    String permissionLabel, {
    required bool isLocation,
  }) async {
    if (!mounted) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Open App Settings'),
        content: Text(
          'Grant "$permissionLabel" in Settings.\n\n'
          'After allowing it, press the Recent Apps button '
          'and tap this app to return.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Go to Settings'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    if (isLocation) {
      await Geolocator.openAppSettings();
    } else {
      await openAppSettings();
    }
    // _checkAll() will be called by didChangeAppLifecycleState(resumed)
    // when the user returns from settings — same as CurrentLocationPickerScreen.
  }

  Future<void> _requestForeground() async {
    setState(() => _foregroundRequesting = true);

    LocationPermission perm = await Geolocator.checkPermission();
    if (!mounted) return;

    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (!mounted) return;
    }

    if (perm == LocationPermission.deniedForever) {
      setState(() => _foregroundRequesting = false);
      await _goToSettings('Location (Foreground)', isLocation: true);
      return;
    }

    await _checkAll();
  }

  Future<void> _requestBackground() async {
    if (!_foregroundGranted) {
      if (mounted) showInfoSnack(context, 'Allow foreground location first');
      return;
    }

    setState(() => _backgroundRequesting = true);

    // Try requesting background location in-app first.
    // On Android 11+ this shows the "Allow all the time" system dialog
    // inside the app — no external settings, no process kill.
    final PermissionStatus bgStatus =
        await Permission.locationAlways.request();
    if (!mounted) return;

    if (bgStatus.isGranted) {
      // Granted via in-app dialog — process stays alive.
      await _checkAll();
      return;
    }

    setState(() => _backgroundRequesting = false);

    // In-app request failed: permanently denied or system redirected to
    // settings. Open settings as last resort.
    await _goToSettings('Location (All the time)', isLocation: true);
  }

  Future<void> _requestNotification() async {
    setState(() => _notificationRequesting = true);

    // Step 1: Request Android 13+ POST_NOTIFICATIONS OS permission.
    final PermissionStatus status = await Permission.notification.request();
    if (!mounted) return;

    // isPermanentlyDenied catches the normal case. The shouldShowRequestRationale
    // check catches the case where the permission is blocked in system settings
    // but status came back as denied (can happen after data clear / reinstall).
    final bool blocked = status.isPermanentlyDenied ||
        (status.isDenied &&
            !await Permission.notification.shouldShowRequestRationale);
    if (!mounted) return;

    if (blocked) {
      setState(() => _notificationRequesting = false);
      await _goToSettings('Notifications', isLocation: false);
      return;
    }

    if (status.isGranted) {
      // Step 2: Request FCM permission so Firebase is aware the OS granted
      // notification access (critical on iOS; also needed on Android 13+).
      try {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {
        // Non-fatal — OS permission is already granted above.
      }

      // Step 3: Register FCM token with the backend so push notifications
      // are delivered. This is a no-op if already subscribed.
      if (mounted) {
        unawaited(FCMService().subscribe(AppScope.of(context)));
      }
    }

    if (!mounted) return;
    await _checkAll();
  }

  Future<void> _requestCall() async {
    setState(() => _callRequesting = true);

    final PermissionStatus status = await Permission.phone.request();
    if (!mounted) return;

    final bool blocked = status.isPermanentlyDenied ||
        (status.isDenied &&
            !await Permission.phone.shouldShowRequestRationale);
    if (!mounted) return;

    if (blocked) {
      setState(() => _callRequesting = false);
      await _goToSettings('Phone calls', isLocation: false);
      return;
    }

    await _checkAll();
  }

  @override
  Widget build(BuildContext context) {
    final bool allGranted = _foregroundGranted &&
        _backgroundGranted &&
        _notificationGranted &&
        _callGranted;

    return AppShell(
      title: 'Permission Setup',
      subtitle: 'Location + notifications are mandatory for order matching',
      child: !_initialized
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
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
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
                                ? () => _goToSettings(
                                    'Location (Foreground)',
                                    isLocation: true)
                                : _requestForeground,
                        onEdit: () => _goToSettings(
                            'Location (Foreground)',
                            isLocation: true),
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
                                ? () => _goToSettings(
                                    'Location (All the time)',
                                    isLocation: true)
                                : _requestBackground,
                        onEdit: () => _goToSettings(
                            'Location (All the time)',
                            isLocation: true),
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
                                ? () => _goToSettings(
                                    'Notifications',
                                    isLocation: false)
                                : _requestNotification,
                        onEdit: () => _goToSettings(
                            'Notifications',
                            isLocation: false),
                      ),
                      const Divider(height: 1),
                      _PermissionRow(
                        icon: Icons.phone_rounded,
                        title: 'Phone calls',
                        subtitle: 'Required to call customers and support',
                        granted: _callGranted,
                        permanentlyDenied: _callPermanentlyDenied,
                        loading: _callRequesting,
                        onTap: _callGranted
                            ? null
                            : _callPermanentlyDenied
                                ? () => _goToSettings(
                                    'Phone calls',
                                    isLocation: false)
                                : _requestCall,
                        onEdit: () => _goToSettings(
                            'Phone calls',
                            isLocation: false),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: allGranted
                      ? () =>
                          Navigator.of(context).pushNamed(AppRoutes.tracking)
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
    required this.onEdit,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final bool permanentlyDenied;
  final bool loading;
  final VoidCallback? onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final Color accent = granted
        ? const Color(0xFF4CAF50)
        : permanentlyDenied
            ? Colors.red
            : Colors.orange;

    final String actionLabel = permanentlyDenied ? 'Open Settings' : 'Allow';

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
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: accent, size: 22),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      color: Colors.grey,
                      tooltip: 'Change in Settings',
                      onPressed: onEdit,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                )
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
