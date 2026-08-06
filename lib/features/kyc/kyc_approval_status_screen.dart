import 'dart:async';
import 'dart:math';

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
    if (elapsed.inSeconds < 45) return 'Last checked just now';
    if (elapsed.inMinutes < 1) return 'Last checked ${elapsed.inSeconds}s ago';
    return 'Last checked ${elapsed.inMinutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final _Phase phase = _celebrating
        ? _Phase.approved
        : app.kycApprovalStatus == VerificationStatus.rejected
        ? _Phase.rejected
        : _Phase.pending;
    final bool rejected = phase == _Phase.rejected;
    final Color tintContainer = rejected
        ? context.dangerContainer
        : context.infoContainer;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.surface,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: phase == _Phase.approved
              ? const _ApprovedView(key: ValueKey('approved'))
              : SafeArea(
                  key: const ValueKey('review'),
                  child: Column(
                    children: [
                      // Tinted header: the focal moment (badge + headline).
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              tintContainer.withValues(
                                alpha: context.isDark ? 0.4 : 0.55,
                              ),
                              context.surface,
                            ],
                          ),
                        ),
                        child: Column(
                          children: [
                            _HeroBadge(rejected: rejected),
                            const SizedBox(height: 20),
                            Text(
                              rejected
                                  ? 'Documents need attention'
                                  : 'Verifying your documents',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: context.textPrimary,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              rejected
                                  ? 'We reviewed your submission and found an issue that needs fixing.'
                                  : 'Our team is reviewing your submitted documents.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: context.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      // Body sheet: details, help, and actions.
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                          child: Column(
                            children: [
                              _StepperHeader(rejected: rejected),
                              const SizedBox(height: 24),
                              if (rejected)
                                _ReasonCard(reason: app.kycRejectionReason)
                              else
                                const _ChecklistCard(),
                              const SizedBox(height: 16),
                              const _HelpSupportRow(),
                              const SizedBox(height: 24),
                              if (rejected)
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: ElevatedButton.icon(
                                    onPressed: _resubmit,
                                    icon: const Icon(Icons.upload_rounded),
                                    label: const Text('Resubmit documents'),
                                  ),
                                )
                              else ...[
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: OutlinedButton.icon(
                                    onPressed: _refreshing ? null : _refresh,
                                    icon: _refreshing
                                        ? SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: context.textSecondary,
                                            ),
                                          )
                                        : const Icon(Icons.refresh_rounded),
                                    label: Text(
                                      _refreshing
                                          ? 'Checking...'
                                          : 'Check status',
                                    ),
                                  ),
                                ),
                                if (_lastCheckedLabel() != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    _lastCheckedLabel()!,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: context.textTertiary),
                                  ),
                                ],
                              ],
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _logout,
                                child: Text(
                                  'Logout',
                                  style: TextStyle(
                                    color: context.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _StepperHeader extends StatelessWidget {
  const _StepperHeader({required this.rejected});
  final bool rejected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepNode(
          label: 'Submitted',
          state: _NodeState.done,
        ),
        _StepConnector(filled: true),
        _StepNode(
          label: 'Review',
          state: rejected ? _NodeState.error : _NodeState.active,
        ),
        _StepConnector(filled: false),
        _StepNode(
          label: rejected ? 'Rejected' : 'Approved',
          state: _NodeState.upcoming,
        ),
      ],
    );
  }
}

enum _NodeState { done, active, error, upcoming }

class _StepNode extends StatelessWidget {
  const _StepNode({required this.label, required this.state});
  final String label;
  final _NodeState state;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (state) {
      _NodeState.done => context.success,
      _NodeState.active => context.info,
      _NodeState.error => context.danger,
      _NodeState.upcoming => context.textTertiary,
    };
    final IconData icon = switch (state) {
      _NodeState.done => Icons.check,
      _NodeState.active => Icons.more_horiz,
      _NodeState.error => Icons.close,
      _NodeState.upcoming => Icons.circle,
    };
    Widget dot = Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: state == _NodeState.upcoming
            ? Colors.transparent
            : color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(
          color: state == _NodeState.upcoming ? context.borderMuted : color,
          width: state == _NodeState.upcoming ? 1.5 : 0,
        ),
      ),
      child: state == _NodeState.upcoming
          ? null
          : Icon(icon, size: 14, color: color),
    );
    if (state == _NodeState.active) {
      dot = dot
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(
            duration: 900.ms,
            begin: const Offset(1, 1),
            end: const Offset(1.15, 1.15),
            curve: Curves.easeInOut,
          );
    }
    return Column(
      children: [
        dot,
        const SizedBox(height: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: state == _NodeState.upcoming
                ? context.textTertiary
                : context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector({required this.filled});
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Container(
          height: 2,
          color: filled ? context.success : context.borderMuted,
        ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.rejected});
  final bool rejected;

  @override
  Widget build(BuildContext context) {
    // Blue for "in progress," distinct from amber/red/green so the three
    // states (checking / rejected / approved) never overlap in meaning —
    // amber read as more alarming ("caution") than intended for pending.
    final Color tint = rejected ? context.danger : context.info;
    final Color tintContainer = rejected
        ? context.dangerContainer
        : context.infoContainer;

    Widget core = Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tintContainer, tint.withValues(alpha: 0.16)],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: context.shadowColor,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(
        rejected ? Icons.badge_rounded : Icons.document_scanner_rounded,
        size: 44,
        color: tint,
      ),
    );
    core = rejected
        ? core.animate().shake(hz: 3, duration: 500.ms, curve: Curves.easeOut)
        : core
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                duration: 2200.ms,
                begin: const Offset(1, 1),
                end: const Offset(1.05, 1.05),
                curve: Curves.easeInOut,
              );

    final Widget chip = Positioned(
      right: -2,
      bottom: -2,
      child:
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: context.surface,
              shape: BoxShape.circle,
              border: Border.all(color: context.surface, width: 3),
            ),
            child: Container(
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(
                rejected ? Icons.priority_high_rounded : Icons.search_rounded,
                size: 15,
                color: Colors.white,
              ),
            ),
          ).animate().fadeIn(delay: 300.ms, duration: 300.ms).scale(
            delay: 300.ms,
            duration: 300.ms,
            curve: Curves.easeOutBack,
            begin: const Offset(0.4, 0.4),
            end: const Offset(1, 1),
          ),
    );

    return SizedBox(
      width: 148,
      height: 148,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!rejected) _SparkleField(color: tint),
          Stack(clipBehavior: Clip.none, children: [core, chip]),
        ],
      ),
    );
  }
}

class _HelpSupportRow extends StatelessWidget {
  const _HelpSupportRow();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.support),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.infoContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.support_agent_rounded,
                  size: 18,
                  color: context.info,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need help?',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Contact support about your verification',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: context.textTertiary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SparkleField extends StatelessWidget {
  const _SparkleField({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    const int count = 7;
    const double fieldSize = 160;
    final Random rnd = Random(3);
    return SizedBox(
      width: fieldSize,
      height: fieldSize,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(count, (i) {
          final double angle = (i / count) * 2 * pi + rnd.nextDouble() * 0.5;
          final double radius = 52 + rnd.nextInt(24).toDouble();
          final double dx = cos(angle) * radius;
          final double dy = sin(angle) * radius;
          final double size = 8 + rnd.nextInt(8).toDouble();
          return Positioned(
            left: fieldSize / 2 + dx - size / 2,
            top: fieldSize / 2 + dy - size / 2,
            child: Icon(Icons.auto_awesome_rounded, size: size, color: color)
                .animate(
                  onPlay: (c) => c.repeat(reverse: true),
                  delay: (i * 230).ms,
                )
                .fadeIn(
                  duration: 850.ms + (i * 40).ms,
                  curve: Curves.easeInOut,
                )
                .scale(
                  duration: 850.ms + (i * 40).ms,
                  begin: const Offset(0.4, 0.4),
                  end: const Offset(1.1, 1.1),
                  curve: Curves.easeInOut,
                ),
          );
        }),
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard();

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      children: [
        _ProgressRow(label: 'Documents received', state: _NodeState.done),
        _ProgressRow(
          label: 'Verification in progress',
          state: _NodeState.active,
        ),
        _ProgressRow(
          label: "You'll be notified as soon as it's reviewed",
          state: _NodeState.upcoming,
        ),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.label, required this.state});
  final String label;
  final _NodeState state;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (state) {
      _NodeState.done => context.success,
      _NodeState.active => context.info,
      _NodeState.error => context.danger,
      _NodeState.upcoming => context.textTertiary,
    };
    final IconData icon = switch (state) {
      _NodeState.done => Icons.check_circle_rounded,
      _NodeState.active => Icons.radio_button_checked_rounded,
      _NodeState.error => Icons.cancel_rounded,
      _NodeState.upcoming => Icons.radio_button_unchecked_rounded,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: state == _NodeState.upcoming
                    ? context.textSecondary
                    : context.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasonCard extends StatelessWidget {
  const _ReasonCard({required this.reason});
  final String? reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: context.shadowColor,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: context.danger,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(18),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: context.dangerContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.priority_high_rounded,
                            size: 15,
                            color: context.danger,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Verification failed',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: context.danger,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      reason ??
                          'Your submission could not be verified. Please review the details and try again.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.textPrimary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 15,
                          color: context.textTertiary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Make sure your documents are clear and the details match your profile before resubmitting.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: context.textTertiary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

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
