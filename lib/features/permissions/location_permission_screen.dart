import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/context_colors.dart';

const Color _kAccent = Color(0xFF4F46E5);

// Brand indigo tint — no central token for the accent's soft background.
Color _accentSoft(BuildContext c) =>
    c.isDark ? const Color(0xFF2B274F) : const Color(0xFFEEF0FF);

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
      await openAppSettings();
    } else {
      await Geolocator.requestPermission();
    }
    await _checkAllPermissions();
  }

  Future<void> _requestBackgroundLocation() async {
    if (!_foregroundGranted) {
      await Geolocator.requestPermission();
    }
    final status = await Permission.locationAlways.status;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    } else {
      await Permission.locationAlways.request();
    }
    await _checkAllPermissions();
  }

  Future<void> _requestNotification() async {
    final status = await Permission.notification.status;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    } else {
      await Permission.notification.request();
    }
    await _checkAllPermissions();
  }

  bool get _allGranted =>
      _foregroundGranted && _backgroundGranted && _notificationGranted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _PermissionHeader(onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  const _InfoBanner(),
                  const SizedBox(height: 16),
                  if (_checking)
                    Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: context.cardColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: context.borderSubtle),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(_kAccent),
                        ),
                      ),
                    )
                  else
                    _PermissionStack(
                      foregroundGranted: _foregroundGranted,
                      backgroundGranted: _backgroundGranted,
                      notificationGranted: _notificationGranted,
                      onTapForeground: _requestForegroundLocation,
                      onTapBackground: _requestBackgroundLocation,
                      onTapNotification: _requestNotification,
                    ),
                  const SizedBox(height: 14),
                  _OpenSettingsTile(onTap: () => openAppSettings()),
                ],
              ),
            ),
            _BottomCta(
              enabled: _allGranted,
              onPressed: _allGranted
                  ? () =>
                      Navigator.of(context).pushNamed(AppRoutes.tracking)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionHeader extends StatelessWidget {
  const _PermissionHeader({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _BackChip(onTap: onBack),
                const SizedBox(height: 14),
                Text(
                  'Permission Setup',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Location + Notifications are mandatory for order matching',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: _accentSoft(context),
                    shape: BoxShape.circle,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Image.asset(
                    'assets/images/permission_shield.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackChip extends StatelessWidget {
  const _BackChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cardBg = context.cardColor;
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderSubtle),
            boxShadow: [
              BoxShadow(
                color: context.shadowColor,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 22,
            color: context.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: _kAccent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.info_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'To receive nearby orders, keep GPS enabled in both '
                  'foreground and background.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Notification access is required for instant order alerts.',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionStack extends StatelessWidget {
  const _PermissionStack({
    required this.foregroundGranted,
    required this.backgroundGranted,
    required this.notificationGranted,
    required this.onTapForeground,
    required this.onTapBackground,
    required this.onTapNotification,
  });

  final bool foregroundGranted;
  final bool backgroundGranted;
  final bool notificationGranted;
  final VoidCallback? onTapForeground;
  final VoidCallback? onTapBackground;
  final VoidCallback? onTapNotification;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        children: [
          _PermissionRow(
            icon: Icons.location_on_rounded,
            iconColor: context.info,
            iconBg: context.infoContainer,
            title: 'Foreground Location',
            description:
                "Allows the app to access your location while you're using the app.",
            granted: foregroundGranted,
            onTap: onTapForeground,
          ),
          _RowDivider(),
          _PermissionRow(
            icon: Icons.gps_fixed_rounded,
            iconColor: const Color(0xFF7C3AED),
            iconBg: context.isDark
                ? const Color(0xFF2D2148)
                : const Color(0xFFEFE9FE),
            title: 'Background Location',
            description:
                'Lets us keep finding orders even when the app is running in background.',
            granted: backgroundGranted,
            grantedSuffix: '(Always)',
            onTap: onTapBackground,
          ),
          _RowDivider(),
          _PermissionRow(
            icon: Icons.notifications_rounded,
            iconColor: context.warning,
            iconBg: context.warningContainer,
            title: 'Notifications',
            description:
                'Get real-time alerts for new orders and important updates.',
            granted: notificationGranted,
            onTap: onTapNotification,
          ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Divider(height: 1, thickness: 1),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.description,
    required this.granted,
    required this.onTap,
    this.grantedSuffix,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String description;
  final bool granted;
  final VoidCallback? onTap;
  final String? grantedSuffix;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 28, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _PermissionStatus(
              granted: granted,
              suffix: grantedSuffix,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionStatus extends StatelessWidget {
  const _PermissionStatus({required this.granted, this.suffix});
  final bool granted;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: granted ? context.success : context.fillMuted,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            granted ? Icons.check_rounded : Icons.priority_high_rounded,
            size: 18,
            color: granted ? Colors.white : context.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: granted
                ? context.successContainer
                : context.dangerContainer,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            granted ? 'Granted' : 'Pending',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: granted ? context.success : context.danger,
            ),
          ),
        ),
        if (suffix != null && granted) ...[
          const SizedBox(height: 2),
          Text(
            suffix!,
            style: TextStyle(
              fontSize: 11,
              color: context.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _OpenSettingsTile extends StatelessWidget {
  const _OpenSettingsTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cardBg = context.cardColor;
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _accentSoft(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.settings_rounded,
                  color: _kAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Open App Settings',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.textSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomCta extends StatelessWidget {
  const _BottomCta({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: context.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(alpha: context.isDark ? 0.4 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: enabled ? 1.0 : 0.55,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          color: const Color(0xFF4F46E5)
                              .withValues(alpha: 0.28),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPressed,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.shield_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'Continue to Tracking Setup',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: context.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Your privacy and data are safe with us',
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
