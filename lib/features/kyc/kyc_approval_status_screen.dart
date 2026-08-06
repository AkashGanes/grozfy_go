import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/state/providers.dart';
import '../../core/theme/context_colors.dart';

enum _Phase { pending, rejected, approved }

// Fixed "premium fintech" dark palette for the pending/rejected states —
// deliberately independent of the app's light/dark theme tokens, same as
// how an onboarding/paywall moment often keeps one consistent brand look
// regardless of system theme. The approved celebration screen below keeps
// using the adaptive context_colors tokens as before.
const Color _kBgTop = Color(0xFF111827);
const Color _kBgBottom = Color(0xFF0D111F);
const Color _kBlue = Color(0xFF3B82F6);
const Color _kPurple = Color(0xFF8B5CF6);
const Color _kRed = Color(0xFFF87171);
const Color _kGreen = Color(0xFF34D399);
const Color _kTextPrimary = Color(0xFFF3F4F6);
const Color _kTextSecondary = Color(0xFF9CA3AF);
const Color _kTextTertiary = Color(0xFF6B7280);

/// Shown after a driver submits identity documents and while their KYC
/// review is Pending or Rejected. Polls for a decision so approval/rejection
/// lands here without the driver needing to background/foreground the app,
/// and holds on a brief celebratory beat before handing off to the dashboard.
class KycApprovalStatusScreen extends ConsumerStatefulWidget {
  const KycApprovalStatusScreen({super.key});

  @override
  ConsumerState<KycApprovalStatusScreen> createState() =>
      _KycApprovalStatusScreenState();
}

class _KycApprovalStatusScreenState
    extends ConsumerState<KycApprovalStatusScreen>
    with WidgetsBindingObserver {
  Timer? _pollTimer;
  bool _refreshing = false;
  bool _celebrating = false;
  bool _navigateScheduled = false;
  DateTime? _lastChecked;
  late AppController _app;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = AppScope.of(context);
    if (_app.kycApprovalStatus == VerificationStatus.approved &&
        !_navigateScheduled) {
      _navigateScheduled = true;
      _pollTimer?.cancel();
      setState(() => _celebrating = true);
      Future.delayed(const Duration(milliseconds: 2200), () {
        if (mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.dashboard, (_) => false);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted || _refreshing || _celebrating) return;
    setState(() => _refreshing = true);
    final app = ref.read(appControllerProvider);
    await app.fetchLoggedInEmployeeDriverProfile(forceRefresh: true);
    if (mounted) {
      setState(() {
        _refreshing = false;
        _lastChecked = DateTime.now();
      });
    }
  }

  Future<void> _logout() async {
    final NavigatorState navigator = Navigator.of(context);
    final app = ref.read(appControllerProvider);
    navigator.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    await app.logout();
  }

  void _resubmit() {
    Navigator.of(context).pushReplacementNamed(AppRoutes.kycDocuments);
  }

  String? _lastCheckedLabel() {
    if (_lastChecked == null) return null;
    final Duration elapsed = DateTime.now().difference(_lastChecked!);
    if (elapsed.inSeconds < 45) return 'Checked just now';
    if (elapsed.inMinutes < 1) return 'Checked ${elapsed.inSeconds}s ago';
    return 'Checked ${elapsed.inMinutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final _Phase phase = _celebrating
        ? _Phase.approved
        : app.kycApprovalStatus == VerificationStatus.rejected
        ? _Phase.rejected
        : _Phase.pending;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: phase == _Phase.approved ? context.surface : _kBgBottom,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: switch (phase) {
            _Phase.approved => const _ApprovedView(key: ValueKey('approved')),
            _Phase.rejected => _RejectedView(
              key: const ValueKey('rejected'),
              reason: app.kycRejectionReason,
              onResubmit: _resubmit,
              onLogout: _logout,
            ),
            _Phase.pending => _PendingView(
              key: const ValueKey('pending'),
              refreshing: _refreshing,
              lastCheckedLabel: _lastCheckedLabel(),
              onRefresh: _refresh,
              onLogout: _logout,
            ),
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared premium shell + primitives
// ---------------------------------------------------------------------------

class _DarkShell extends StatelessWidget {
  const _DarkShell({required this.glowColor, required this.child});
  final Color glowColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kBgTop, _kBgBottom],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -70,
            left: -70,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kBlue.withValues(alpha: 0.18),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -90,
            right: -70,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowColor.withValues(alpha: 0.16),
                ),
              ),
            ),
          ),
          SafeArea(child: child),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderColor,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: 0.10)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Press-scale micro-interaction. Uses raw pointer events (not a
/// GestureDetector) so it never steals the tap gesture from an InkWell
/// placed inside `child` — it only observes, it doesn't handle.
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child});
  final Widget child;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: 1),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.5),
          ),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(
      duration: 2200.ms,
      color: color.withValues(alpha: 0.5),
    );
  }
}

enum _TState { done, active, error, upcoming }

class _Timeline extends StatelessWidget {
  const _Timeline({required this.rejected});
  final bool rejected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _TimelineNode(label: 'Submitted', state: _TState.done),
        const _TimelineConnector(filled: true),
        _TimelineNode(label: 'Review', state: rejected ? _TState.error : _TState.active),
        _TimelineConnector(filled: false),
        _TimelineNode(label: rejected ? 'Rejected' : 'Approved', state: _TState.upcoming),
      ],
    );
  }
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({required this.label, required this.state});
  final String label;
  final _TState state;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (state) {
      _TState.done => _kGreen,
      _TState.active => _kBlue,
      _TState.error => _kRed,
      _TState.upcoming => _kTextTertiary,
    };
    final IconData icon = switch (state) {
      _TState.done => Icons.check_rounded,
      _TState.active => Icons.autorenew_rounded,
      _TState.error => Icons.close_rounded,
      _TState.upcoming => Icons.circle,
    };
    Widget dot = Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: state == _TState.upcoming ? Colors.transparent : color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(
          color: state == _TState.upcoming ? Colors.white.withValues(alpha: 0.16) : color,
          width: state == _TState.upcoming ? 1.5 : 0,
        ),
        boxShadow: state == _TState.active
            ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 14, spreadRadius: 1)]
            : null,
      ),
      child: state == _TState.upcoming ? null : Icon(icon, size: 14, color: color),
    );
    if (state == _TState.active) {
      dot = dot
          .animate(onPlay: (c) => c.repeat())
          .rotate(duration: 1400.ms, curve: Curves.linear, begin: 0, end: 1);
    }
    return Column(
      children: [
        dot,
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: state == _TState.upcoming ? _kTextTertiary : _kTextPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}

class _TimelineConnector extends StatelessWidget {
  const _TimelineConnector({required this.filled});
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: filled
                ? const LinearGradient(colors: [_kGreen, _kBlue])
                : LinearGradient(colors: [
                    Colors.white.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0.12),
                  ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending screen
// ---------------------------------------------------------------------------

class _PendingView extends StatelessWidget {
  const _PendingView({
    super.key,
    required this.refreshing,
    required this.lastCheckedLabel,
    required this.onRefresh,
    required this.onLogout,
  });
  final bool refreshing;
  final String? lastCheckedLabel;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return _DarkShell(
      glowColor: _kPurple,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: Column(
          children: [
            const _ScanIllustration()
                .animate()
                .fadeIn(duration: 500.ms)
                .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1), curve: Curves.easeOutBack),
            const SizedBox(height: 24),
            Text(
              "We're reviewing your documents",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: _kTextPrimary,
                fontWeight: FontWeight.w800,
              ),
            ).animate().fadeIn(delay: 120.ms, duration: 400.ms).moveY(begin: 10, end: 0),
            const SizedBox(height: 8),
            const Text(
              'Our team is reviewing your submitted documents.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kTextSecondary, fontSize: 14, height: 1.4),
            ).animate().fadeIn(delay: 180.ms, duration: 400.ms).moveY(begin: 10, end: 0),
            const SizedBox(height: 20),
            const _StatusPill(
              label: 'PENDING REVIEW',
              color: _kBlue,
            ).animate().fadeIn(delay: 240.ms, duration: 400.ms),
            const SizedBox(height: 30),
            const _Timeline(
              rejected: false,
            ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
            const SizedBox(height: 26),
            const _WhatsHappeningCard()
                .animate()
                .fadeIn(delay: 380.ms, duration: 400.ms)
                .moveY(begin: 14, end: 0),
            const SizedBox(height: 12),
            _PressScale(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: refreshing ? null : onRefresh,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (refreshing)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _kBlue),
                          )
                        else
                          const Icon(Icons.refresh_rounded, size: 14, color: _kBlue),
                        const SizedBox(width: 6),
                        Text(
                          refreshing ? 'Checking...' : 'Check now',
                          style: const TextStyle(color: _kBlue, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        if (lastCheckedLabel != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '· $lastCheckedLabel',
                            style: const TextStyle(color: _kTextTertiary, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const _HelpCard().animate().fadeIn(delay: 460.ms, duration: 400.ms).moveY(begin: 14, end: 0),
            const SizedBox(height: 14),
            const _SecurityCard().animate().fadeIn(delay: 520.ms, duration: 400.ms).moveY(begin: 14, end: 0),
            const SizedBox(height: 24),
            TextButton(
              onPressed: onLogout,
              child: const Text('Logout', style: TextStyle(color: _kTextTertiary)),
            ),
          ],
        ),
      ),
    );
  }
}

class _WhatsHappeningCard extends StatelessWidget {
  const _WhatsHappeningCard();

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StatusRow(icon: Icons.check_circle_rounded, color: _kGreen, label: 'Documents received'),
          const SizedBox(height: 16),
          const _StatusRow(
            icon: Icons.autorenew_rounded,
            color: _kBlue,
            label: 'Verification in progress',
            spinning: true,
            shimmerText: true,
          ),
          const SizedBox(height: 16),
          const _StatusRow(
            icon: Icons.notifications_none_rounded,
            color: _kTextTertiary,
            label: "You'll be notified once approved",
            muted: true,
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.color,
    required this.label,
    this.spinning = false,
    this.shimmerText = false,
    this.muted = false,
  });
  final IconData icon;
  final Color color;
  final String label;
  final bool spinning;
  final bool shimmerText;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: Icon(icon, size: 15, color: color),
    );
    if (spinning) {
      iconWidget = iconWidget
          .animate(onPlay: (c) => c.repeat())
          .rotate(duration: 1600.ms, curve: Curves.linear, begin: 0, end: 1);
    }
    final TextStyle style = TextStyle(
      color: muted ? _kTextTertiary : _kTextPrimary,
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
    );
    Widget text = Text(label, style: style);
    if (shimmerText) {
      text = text.animate(onPlay: (c) => c.repeat()).shimmer(
        duration: 1800.ms,
        color: Colors.white.withValues(alpha: 0.9),
      );
    }
    return Row(
      children: [
        iconWidget,
        const SizedBox(width: 12),
        Expanded(child: text),
      ],
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard();

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      child: _GlassCard(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.support),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [_kBlue, _kPurple]),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.support_agent_rounded, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Need help?',
                          style: TextStyle(color: _kTextPrimary, fontWeight: FontWeight.w700, fontSize: 14.5),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Contact support about your verification',
                          style: TextStyle(color: _kTextTertiary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: _kTextTertiary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard();

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _kGreen.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: const Icon(Icons.verified_user_rounded, size: 18, color: _kGreen),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Your data is encrypted and protected.',
              style: TextStyle(color: _kTextSecondary, fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending illustration — floating document, magnifier, scan sweep, particles
// ---------------------------------------------------------------------------

class _ScanIllustration extends StatelessWidget {
  const _ScanIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: const [
          _ParticleField(colors: [_kBlue, _kPurple]),
          _FloatingDocument(),
        ],
      ),
    );
  }
}

class _FloatingDocument extends StatelessWidget {
  const _FloatingDocument();

  @override
  Widget build(BuildContext context) {
    return Container(
          width: 108,
          height: 136,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E293B), Color(0xFF111827)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(color: _kBlue.withValues(alpha: 0.28), blurRadius: 32, spreadRadius: 2),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _DocLine(width: 58),
                      SizedBox(height: 8),
                      _DocLine(width: 76),
                      SizedBox(height: 8),
                      _DocLine(width: 42),
                      SizedBox(height: 18),
                      _DocLine(width: 66),
                      SizedBox(height: 8),
                      _DocLine(width: 50),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: double.infinity,
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _kBlue.withValues(alpha: 0),
                            _kBlue,
                            _kBlue.withValues(alpha: 0),
                          ],
                        ),
                        boxShadow: [BoxShadow(color: _kBlue.withValues(alpha: 0.8), blurRadius: 8)],
                      ),
                    ).animate(onPlay: (c) => c.repeat()).moveY(
                      duration: 2000.ms,
                      begin: -66,
                      end: 66,
                      curve: Curves.easeInOut,
                    ),
                  ),
                ),
                Positioned(
                  right: -16,
                  bottom: -12,
                  child:
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [_kBlue, _kPurple]),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _kBlue.withValues(alpha: 0.5),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                      ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
                        duration: 1600.ms,
                        begin: const Offset(1, 1),
                        end: const Offset(1.08, 1.08),
                        curve: Curves.easeInOut,
                      ),
                ),
              ],
            ),
          ),
        )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .moveY(duration: 2600.ms, begin: -6, end: 6, curve: Curves.easeInOut);
  }
}

class _DocLine extends StatelessWidget {
  const _DocLine({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 6,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(3),
    ),
  );
}

class _ParticleField extends StatelessWidget {
  const _ParticleField({required this.colors});
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    const int count = 10;
    const double field = 220;
    final Random rnd = Random(11);
    return SizedBox(
      width: field,
      height: field,
      child: Stack(
        children: List.generate(count, (i) {
          final double angle = rnd.nextDouble() * 2 * pi;
          final double radius = 55 + rnd.nextDouble() * 65;
          final double dx = cos(angle) * radius;
          final double dy = sin(angle) * radius;
          final double size = 3 + rnd.nextDouble() * 4;
          final Color color = colors[i % colors.length];
          return Positioned(
            left: field / 2 + dx,
            top: field / 2 + dy,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: size * 2)],
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true), delay: (i * 180).ms).fadeIn(
              duration: 1200.ms,
              curve: Curves.easeInOut,
            ).scale(
              duration: 1200.ms,
              begin: const Offset(0.3, 0.3),
              end: const Offset(1, 1),
              curve: Curves.easeInOut,
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rejected screen
// ---------------------------------------------------------------------------

class _RejectedView extends StatelessWidget {
  const _RejectedView({
    super.key,
    required this.reason,
    required this.onResubmit,
    required this.onLogout,
  });
  final String? reason;
  final VoidCallback onResubmit;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return _DarkShell(
      glowColor: _kRed,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: Column(
          children: [
            const _ShieldIllustration()
                .animate()
                .fadeIn(duration: 500.ms)
                .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1), curve: Curves.easeOutBack),
            const SizedBox(height: 24),
            Text(
              'Documents need attention',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: _kTextPrimary,
                fontWeight: FontWeight.w800,
              ),
            ).animate().fadeIn(delay: 120.ms, duration: 400.ms).moveY(begin: 10, end: 0),
            const SizedBox(height: 8),
            const Text(
              'We found some issues with your submitted documents.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kTextSecondary, fontSize: 14, height: 1.4),
            ).animate().fadeIn(delay: 180.ms, duration: 400.ms).moveY(begin: 10, end: 0),
            const SizedBox(height: 26),
            const _Timeline(
              rejected: true,
            ).animate().fadeIn(delay: 260.ms, duration: 400.ms),
            const SizedBox(height: 26),
            _ErrorCard(
              reason: reason,
            ).animate().fadeIn(delay: 340.ms, duration: 400.ms).moveY(begin: 14, end: 0),
            const SizedBox(height: 16),
            const _HowToFixCard()
                .animate()
                .fadeIn(delay: 420.ms, duration: 400.ms)
                .moveY(begin: 14, end: 0),
            const SizedBox(height: 28),
            _GradientButton(
              label: 'Resubmit Documents',
              icon: Icons.upload_rounded,
              onPressed: onResubmit,
            ).animate().fadeIn(delay: 500.ms, duration: 400.ms).moveY(begin: 14, end: 0),
            const SizedBox(height: 12),
            _GhostButton(
              label: 'Contact Support',
              icon: Icons.support_agent_rounded,
              onPressed: () => Navigator.of(context).pushNamed(AppRoutes.support),
            ).animate().fadeIn(delay: 560.ms, duration: 400.ms).moveY(begin: 14, end: 0),
            const SizedBox(height: 20),
            TextButton(
              onPressed: onLogout,
              child: const Text('Logout', style: TextStyle(color: _kTextTertiary)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShieldIllustration extends StatelessWidget {
  const _ShieldIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _kRed.withValues(alpha: 0.28)),
            ),
          ),
          Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3A1520), Color(0xFF1B0F14)],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: _kRed.withValues(alpha: 0.35), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: _kRed.withValues(alpha: 0.45), blurRadius: 36, spreadRadius: 2),
                  ],
                ),
                child: const Icon(Icons.gpp_bad_rounded, size: 56, color: _kRed),
              )
              .animate()
              .shake(hz: 3, duration: 500.ms, curve: Curves.easeOut)
              .animate(onPlay: (c) => c.repeat(reverse: true), delay: 700.ms)
              .scale(
                duration: 2400.ms,
                begin: const Offset(1, 1),
                end: const Offset(1.04, 1.04),
                curve: Curves.easeInOut,
              ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.reason});
  final String? reason;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      borderColor: _kRed.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _kRed.withValues(alpha: 0.16), shape: BoxShape.circle),
                child: const Icon(Icons.error_rounded, size: 15, color: _kRed),
              ),
              const SizedBox(width: 10),
              const Text(
                'Verification failed',
                style: TextStyle(color: _kRed, fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              reason ?? 'Your submission could not be verified. Please review the details and try again.',
              style: const TextStyle(color: _kTextPrimary, fontSize: 13.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _HowToFixCard extends StatelessWidget {
  const _HowToFixCard();

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How to fix',
            style: TextStyle(color: _kTextPrimary, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 16),
          const _TipRow(icon: Icons.camera_alt_rounded, label: 'Upload a clearer document'),
          const SizedBox(height: 14),
          const _TipRow(icon: Icons.badge_rounded, label: 'Ensure details match your profile'),
          const SizedBox(height: 14),
          const _TipRow(icon: Icons.refresh_rounded, label: 'Submit again'),
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), shape: BoxShape.circle),
          child: Icon(icon, size: 15, color: _kBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 13.5)),
        ),
      ],
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_kBlue, _kPurple]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: _kPurple.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 19),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          color: Colors.white.withValues(alpha: 0.03),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: _kTextSecondary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(color: _kTextSecondary, fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Approved celebration — unchanged, adaptive light/dark theme (out of scope
// for the premium-dark redesign, which only covers pending/rejected).
// ---------------------------------------------------------------------------

class _ApprovedView extends StatelessWidget {
  const _ApprovedView({super.key});

  static const Duration _redirectDelay = Duration(milliseconds: 2200);

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('approved-center'),
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 1.1,
          colors: [
            context.successContainer.withValues(alpha: context.isDark ? 0.55 : 0.7),
            context.surface,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _CelebrationBadge(),
            const SizedBox(height: 28),
            Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: context.successContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 14,
                        color: context.success,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'KYC VERIFIED',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(
                              color: context.success,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                      ),
                    ],
                  ),
                )
                .animate()
                .fadeIn(delay: 150.ms, duration: 350.ms)
                .moveY(begin: 8, end: 0),
            const SizedBox(height: 16),
            Text(
                  "You're approved!",
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                )
                .animate()
                .fadeIn(delay: 250.ms, duration: 400.ms)
                .moveY(begin: 10, end: 0),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                    'Your KYC documents have been verified. Taking you to your dashboard...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  )
                  .animate()
                  .fadeIn(delay: 400.ms, duration: 400.ms)
                  .moveY(begin: 10, end: 0),
            ),
            const SizedBox(height: 32),
            _RedirectProgressBar(duration: _redirectDelay)
                .animate()
                .fadeIn(delay: 550.ms, duration: 300.ms),
          ],
        ),
      ),
    );
  }
}

class _CelebrationBadge extends StatelessWidget {
  const _CelebrationBadge();

  @override
  Widget build(BuildContext context) {
    final Random rnd = Random(7);
    const List<IconData> confettiShapes = [
      Icons.circle,
      Icons.square_rounded,
      Icons.star_rounded,
    ];
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // One-shot ripple burst behind the badge.
          Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: context.success, width: 2),
                ),
              )
              .animate()
              .scale(
                delay: 150.ms,
                duration: 700.ms,
                curve: Curves.easeOut,
                begin: const Offset(1, 1),
                end: const Offset(2.1, 2.1),
              )
              .fadeOut(delay: 150.ms, duration: 700.ms, curve: Curves.easeOut),
          // Mixed-shape confetti burst.
          ...List.generate(14, (i) {
            final double angle = (i / 14) * 2 * pi + rnd.nextDouble() * 0.3;
            final double distance = 70 + rnd.nextInt(30).toDouble();
            final double dx = cos(angle) * distance;
            final double dy = sin(angle) * distance;
            final Color dotColor =
                [
                  context.success,
                  context.info,
                  context.warning,
                ][i % 3];
            final IconData shape = confettiShapes[i % confettiShapes.length];
            return Positioned(
              left: 100 + dx,
              top: 100 + dy,
              child:
                  Icon(shape, size: 8 + rnd.nextInt(6).toDouble(), color: dotColor)
                      .animate(delay: (35 * i).ms)
                      .fadeIn(duration: 200.ms)
                      .scale(begin: const Offset(0.2, 0.2), end: const Offset(1, 1))
                      .then(delay: 350.ms)
                      .fadeOut(duration: 450.ms),
            );
          }),
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: context.successContainer,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: context.success.withValues(alpha: 0.35),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: context.shadowColor,
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(Icons.check_rounded, size: 58, color: context.success),
          ).animate().scale(
            duration: 550.ms,
            curve: Curves.elasticOut,
            begin: const Offset(0.3, 0.3),
            end: const Offset(1, 1),
          ),
        ],
      ),
    );
  }
}

class _RedirectProgressBar extends StatelessWidget {
  const _RedirectProgressBar({required this.duration});
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 5,
          color: context.fillMuted,
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: duration,
            curve: Curves.easeInOut,
            builder: (context, value, _) => FractionallySizedBox(
              widthFactor: value,
              child: Container(color: context.success),
            ),
          ),
        ),
      ),
    );
  }
}
