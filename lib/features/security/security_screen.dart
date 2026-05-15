import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/app_lock_provider.dart';

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen>
    with TickerProviderStateMixin {
  bool _loaded = false;
  bool _deviceSupported = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadDeviceCapabilities();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceCapabilities() async {
    final service = ref.read(localAuthServiceProvider);
    final supported = await service.isDeviceSupported();
    if (!mounted) return;
    setState(() {
      _deviceSupported = supported;
      _loaded = true;
    });
  }

  Future<void> _onToggle(bool enabled) async {
    if (!enabled) {
      await ref.read(appLockEnabledProvider.notifier).toggle(false);
      return;
    }
    final service = ref.read(localAuthServiceProvider);
    final biometricOnly = ref.read(biometricOnlyProvider);
    final success = await service.authenticate(
      reason: 'Verify your identity to enable app lock',
      biometricOnly: biometricOnly,
    );
    if (!mounted) return;
    if (success) {
      await ref.read(appLockEnabledProvider.notifier).toggle(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Authentication failed. App lock was not enabled.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appLockEnabled = ref.watch(appLockEnabledProvider);
    final autoLockIndex = ref.watch(autoLockIndexProvider);
    final biometricOnly = ref.watch(biometricOnlyProvider);
    final toggleEnabled = _loaded && _deviceSupported;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [scheme.surface, Theme.of(context).scaffoldBackgroundColor]
                : const [
                    Color(0xFFF1F7FF),
                    Color(0xFFE8F5F0),
                    Color(0xFFFFF5E6),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            _buildAmbientGlow(scheme, isDark),
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(context, scheme, isDark),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                      children: [
                        _buildHeroSection(scheme, isDark, appLockEnabled),
                        const SizedBox(height: 24),
                        _buildAppLockCard(
                            scheme, isDark, appLockEnabled, toggleEnabled),
                        if (appLockEnabled) ...[
                          const SizedBox(height: 12),
                          _buildStatusBadge(scheme, isDark),
                        ],
                        const SizedBox(height: 12),
                        _buildAutoLockCard(scheme, isDark, appLockEnabled, autoLockIndex),
                        const SizedBox(height: 12),
                        _buildAdvancedCard(scheme, isDark, biometricOnly),
                        const SizedBox(height: 20),
                        _buildInfoCard(scheme, isDark),
                        if (_loaded && !_deviceSupported) ...[
                          const SizedBox(height: 12),
                          _buildNoLockWarning(scheme),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Ambient background glows ────────────────────────────────────────────────

  Widget _buildAmbientGlow(ColorScheme scheme, bool isDark) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -70,
            left: -60,
            child: _glowBlob(
              scheme.primary.withValues(alpha: isDark ? 0.18 : 0.10),
              260,
            ),
          ),
          Positioned(
            top: 200,
            right: -70,
            child: _glowBlob(
              scheme.secondary.withValues(alpha: isDark ? 0.12 : 0.07),
              200,
            ),
          ),
          Positioned(
            bottom: 60,
            left: -40,
            child: _glowBlob(
              scheme.primary.withValues(alpha: isDark ? 0.10 : 0.06),
              170,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glowBlob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────────────

  Widget _buildTopBar(
      BuildContext context, ColorScheme scheme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: isDark ? 0.9 : 0.7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.arrow_back_rounded,
                  color: scheme.onSurface, size: 18),
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Security',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                'Manage your security settings and protect your data.',
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.55),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Hero shield ─────────────────────────────────────────────────────────────

  Widget _buildHeroSection(
      ColorScheme scheme, bool isDark, bool appLockEnabled) {
    final activeColor = scheme.secondary; // mint
    final inactiveColor = scheme.onSurface.withValues(alpha: 0.35);
    final iconColor = appLockEnabled ? activeColor : inactiveColor;

    return Center(
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: appLockEnabled ? _pulseAnimation.value : 1.0,
                child: child,
              );
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow ring
                Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        scheme.primary.withValues(
                            alpha: appLockEnabled ? (isDark ? 0.25 : 0.15) : 0),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // Inner circle
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.surface.withValues(
                        alpha: isDark ? 0.85 : 0.75),
                    border: Border.all(
                      color: appLockEnabled
                          ? scheme.primary.withValues(alpha: 0.5)
                          : scheme.outline.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                    boxShadow: appLockEnabled
                        ? [
                            BoxShadow(
                              color: scheme.primary.withValues(
                                  alpha: isDark ? 0.30 : 0.18),
                              blurRadius: 22,
                              spreadRadius: 3,
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: isDark ? 0.25 : 0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Icon(
                    appLockEnabled
                        ? Icons.shield_rounded
                        : Icons.shield_outlined,
                    color: iconColor,
                    size: 36,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              appLockEnabled ? 'Protection Active' : 'Protection Disabled',
              key: ValueKey(appLockEnabled),
              style: TextStyle(
                color: appLockEnabled
                    ? scheme.secondary
                    : scheme.onSurface.withValues(alpha: 0.45),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── App lock card ───────────────────────────────────────────────────────────

  Widget _buildAppLockCard(
    ColorScheme scheme,
    bool isDark,
    bool appLockEnabled,
    bool toggleEnabled,
  ) {
    return _ThemedCard(
      scheme: scheme,
      isDark: isDark,
      primary: scheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBox(
                icon: appLockEnabled
                    ? Icons.lock_rounded
                    : Icons.lock_open_rounded,
                scheme: scheme,
                isDark: isDark,
                active: appLockEnabled,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'App Lock',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        appLockEnabled
                            ? 'Tap to disable authentication on launch.'
                            : 'Require authentication every time you open the app.',
                        key: ValueKey(appLockEnabled),
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.55),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: appLockEnabled,
                onChanged: toggleEnabled ? _onToggle : null,
                activeThumbColor: Colors.white,
                activeTrackColor: scheme.primary,
                inactiveThumbColor:
                    scheme.onSurface.withValues(alpha: 0.4),
                inactiveTrackColor:
                    scheme.onSurface.withValues(alpha: 0.12),
              ),
            ],
          ),
          if (appLockEnabled) ...[
            const SizedBox(height: 14),
            Divider(
              color: scheme.primary.withValues(alpha: 0.2),
              height: 1,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.verified_rounded,
                    color: scheme.secondary, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Your apps are protected and secured.',
                  style: TextStyle(
                    color: scheme.secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Status badge ────────────────────────────────────────────────────────────

  Widget _buildStatusBadge(ColorScheme scheme, bool isDark) {
    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: isDark ? 0.12 : 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.primary.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PulsingDot(color: scheme.secondary),
            const SizedBox(width: 8),
            Text(
              'Active — Authentication required on every launch',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Auto-lock card ──────────────────────────────────────────────────────────

  Widget _buildAutoLockCard(
      ColorScheme scheme, bool isDark, bool appLockEnabled, int autoLockIndex) {
    return _ThemedCard(
      scheme: scheme,
      isDark: isDark,
      primary: scheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label: 'AUTO-LOCK', scheme: scheme),
          const SizedBox(height: 14),
          Row(
            children: [
              _IconBox(
                icon: Icons.timer_rounded,
                scheme: scheme,
                isDark: isDark,
                active: false,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lock After',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Automatically lock when idle',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: appLockEnabled
                    ? () {
                        final next =
                            (autoLockIndex + 1) % autoLockOptions.length;
                        ref
                            .read(autoLockIndexProvider.notifier)
                            .setIndex(next);
                      }
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: appLockEnabled
                        ? scheme.primary.withValues(alpha: isDark ? 0.18 : 0.10)
                        : scheme.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: appLockEnabled
                          ? scheme.primary.withValues(alpha: 0.35)
                          : scheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    appLockEnabled ? autoLockOptions[autoLockIndex] : '—',
                    style: TextStyle(
                      color: appLockEnabled
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.35),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Advanced settings card ──────────────────────────────────────────────────

  Widget _buildAdvancedCard(
      ColorScheme scheme, bool isDark, bool biometricOnly) {
    return _ThemedCard(
      scheme: scheme,
      isDark: isDark,
      primary: scheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label: 'ADVANCED', scheme: scheme),
          const SizedBox(height: 14),
          _advancedRow(
            scheme: scheme,
            isDark: isDark,
            icon: Icons.fingerprint_rounded,
            title: 'Biometric Only',
            subtitle: biometricOnly
                ? 'PIN/password fallback disabled'
                : 'Allows PIN/password as fallback',
            trailing: Switch(
              value: biometricOnly,
              onChanged: (v) =>
                  ref.read(biometricOnlyProvider.notifier).toggle(v),
              activeThumbColor: Colors.white,
              activeTrackColor: scheme.primary,
              inactiveThumbColor: scheme.onSurface.withValues(alpha: 0.4),
              inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(height: 2),
          Divider(
            color: scheme.outline.withValues(alpha: 0.15),
            height: 20,
          ),
          _advancedRow(
            scheme: scheme,
            isDark: isDark,
            icon: Icons.notifications_off_outlined,
            title: 'Hide Notifications When Locked',
            subtitle: 'Coming soon',
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurface.withValues(alpha: 0.35),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _advancedRow({
    required ColorScheme scheme,
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Row(
      children: [
        _IconBox(icon: icon, scheme: scheme, isDark: isDark, active: false),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        trailing,
      ],
    );
  }

  // ── Info card ───────────────────────────────────────────────────────────────

  Widget _buildInfoCard(ColorScheme scheme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: isDark ? 0.18 : 0.08),
            scheme.secondary.withValues(alpha: isDark ? 0.08 : 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.primary.withValues(alpha: isDark ? 0.30 : 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary
                .withValues(alpha: isDark ? 0.10 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: isDark ? 0.20 : 0.10),
            ),
            child: Icon(Icons.security_rounded,
                color: scheme.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why App Lock Matters',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'App Lock prevents unauthorized access to your account and sensitive delivery data. Even if someone picks up your phone, they cannot open the app without authentication.',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── No-device-lock warning ──────────────────────────────────────────────────

  Widget _buildNoLockWarning(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.tertiary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.tertiary.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: scheme.tertiary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No screen lock detected. Set up a PIN or password in your device settings to enable App Lock.',
              style: TextStyle(
                color: scheme.tertiary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared sub-widgets ───────────────────────────────────────────────────────

class _ThemedCard extends StatelessWidget {
  const _ThemedCard({
    required this.scheme,
    required this.isDark,
    required this.primary,
    required this.child,
  });

  final ColorScheme scheme;
  final bool isDark;
  final Color primary;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 0),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: isDark ? 0.85 : 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? scheme.outline.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: primary.withValues(alpha: isDark ? 0.05 : 0.03),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({
    required this.icon,
    required this.scheme,
    required this.isDark,
    required this.active,
  });

  final IconData icon;
  final ColorScheme scheme;
  final bool isDark;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: active
            ? scheme.primary.withValues(alpha: isDark ? 0.20 : 0.12)
            : scheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? scheme.primary.withValues(alpha: 0.40)
              : scheme.outline.withValues(alpha: 0.18),
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: scheme.primary
                      .withValues(alpha: isDark ? 0.22 : 0.12),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: Icon(
        icon,
        color: active
            ? scheme.primary
            : scheme.onSurface.withValues(alpha: 0.45),
        size: 20,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.scheme});
  final String label;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: scheme.primary.withValues(alpha: 0.8),
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _a = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: _a.value * 0.75),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}
