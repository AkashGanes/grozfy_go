import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/state/providers.dart';
import '../../core/theme/context_colors.dart';

enum _Phase { pending, rejected, approved }

/// Shown after a driver submits identity documents and while their KYC
/// review is Pending or Rejected. Polls for a decision so approval/rejection
/// lands here without the driver needing to background/foreground the app.
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
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
    if (!mounted || _refreshing) return;
    final app = ref.read(appControllerProvider);
    if (app.kycApprovalStatus == VerificationStatus.approved ||
        app.kycApprovalStatus == VerificationStatus.rejected) {
      _pollTimer?.cancel();
      return;
    }
    setState(() => _refreshing = true);
    await app.fetchLoggedInEmployeeDriverProfile(forceRefresh: true);
    if (!mounted) return;
    setState(() => _refreshing = false);
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

  void _goToDashboardNow() {
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.dashboard, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final _Phase phase = switch (app.kycApprovalStatus) {
      VerificationStatus.approved => _Phase.approved,
      VerificationStatus.rejected => _Phase.rejected,
      _ => _Phase.pending,
    };

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.surface,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: switch (phase) {
            _Phase.pending => _MinimalStatusView(
              key: const ValueKey('pending'),
              iconOverride: _HourglassSandIcon(edgeColor: context.borderStrong, size: 96),
              title: 'Verification Pending',
              subtitle: "We're reviewing your documents. This usually takes less than 24 hours.",
              actions: [
                OutlinedButton.icon(
                  onPressed: _refreshing ? null : _refresh,
                  icon: _refreshing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: context.textSecondary),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(_refreshing ? 'Checking...' : 'Check Status'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _logout,
                  child: Text('Logout', style: TextStyle(color: context.textTertiary)),
                ),
              ],
            ),
            _Phase.rejected => _MinimalStatusView(
              key: const ValueKey('rejected'),
              icon: Icons.cancel_rounded,
              iconColor: context.danger,
              iconContainerColor: context.dangerContainer,
              title: 'Verification Rejected',
              subtitle: "We couldn't verify your documents.",
              extra: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.dangerContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  app.kycRejectionReason ??
                      'Your submission could not be verified. Please review your documents and resubmit.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textPrimary, fontSize: 13.5, height: 1.45),
                ),
              ),
              actions: [
                FilledButton.icon(
                  onPressed: _resubmit,
                  icon: const Icon(Icons.upload_rounded, size: 18),
                  label: const Text('Resubmit Documents'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _logout,
                  child: Text('Logout', style: TextStyle(color: context.textTertiary)),
                ),
              ],
            ),
            _Phase.approved => _MinimalStatusView(
              key: const ValueKey('approved'),
              icon: Icons.check_circle_rounded,
              iconColor: context.success,
              iconContainerColor: context.successContainer,
              title: "You're Verified",
              subtitle: 'Your documents have been verified successfully. You can now start delivering and earning.',
              actions: [
                FilledButton.icon(
                  onPressed: _goToDashboardNow,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Continue'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          },
        ),
      ),
    );
  }
}

/// Minimal icon + text status layout shared by the pending/rejected/approved
/// KYC states. Fully theme-adaptive via [context_colors] tokens.
class _MinimalStatusView extends StatelessWidget {
  const _MinimalStatusView({
    super.key,
    this.icon,
    this.iconColor,
    this.iconContainerColor,
    this.iconOverride,
    required this.title,
    required this.subtitle,
    this.extra,
    this.actions = const [],
  });

  final IconData? icon;
  final Color? iconColor;
  final Color? iconContainerColor;
  final Widget? iconOverride;
  final String title;
  final String subtitle;
  final Widget? extra;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    Widget iconWidget;
    if (iconOverride != null) {
      iconWidget = iconOverride!;
    } else {
      iconWidget = Container(
        width: 96,
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: iconContainerColor, shape: BoxShape.circle),
        child: Icon(icon, size: 48, color: iconColor),
      );
    }

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget.animate().fadeIn(duration: 400.ms).scale(
                begin: const Offset(0.85, 0.85),
                end: const Offset(1, 1),
                curve: Curves.easeOutBack,
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: context.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ).animate().fadeIn(delay: 120.ms, duration: 400.ms).moveY(begin: 10, end: 0),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textSecondary, fontSize: 14, height: 1.4),
              ).animate().fadeIn(delay: 180.ms, duration: 400.ms).moveY(begin: 10, end: 0),
              if (extra != null) ...[
                const SizedBox(height: 20),
                extra!.animate().fadeIn(delay: 240.ms, duration: 400.ms).moveY(begin: 10, end: 0),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 28),
                ...actions,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A large hourglass whose sand drains from the top chamber into the bottom
/// one over [_cycleDuration], then does one quick 180° flip in the last 8%
/// of the cycle so the sand can start draining again. Owns its own
/// [AnimationController], so the animation stops automatically the moment
/// this widget is disposed (e.g. when the phase switches away from pending).
class _HourglassSandIcon extends StatefulWidget {
  const _HourglassSandIcon({required this.edgeColor, this.size = 72});

  final Color edgeColor;
  final double size;

  @override
  State<_HourglassSandIcon> createState() => _HourglassSandIconState();
}

class _HourglassSandIconState extends State<_HourglassSandIcon>
    with SingleTickerProviderStateMixin {
  // Sand drains over the first 92% of the cycle; the flip is the last 8%.
  // Both the sand fill and the rotation reset to their start state at
  // exactly the same instant (t wrapping back to 0), so the flip always
  // lands seamlessly back on a freshly-full, upright hourglass.
  static const double _drainFraction = 0.92;
  static const Color _sandColorLight = Color(0xFFFFC107);
  static const Color _sandColorDark = Color(0xFFB8860B);
  static const Duration _cycleDuration = Duration(seconds: 3);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _cycleDuration)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final double t = _controller.value;
        final double progress = (t / _drainFraction).clamp(0.0, 1.0);
        final double flipT = ((t - _drainFraction) / (1 - _drainFraction)).clamp(0.0, 1.0);

        return Transform.rotate(
          angle: flipT * pi,
          child: CustomPaint(
            size: Size(widget.size * 1.1, widget.size * 1.6),
            painter: _HourglassPainter(
              progress: progress,
              edgeColor: widget.edgeColor,
              sandColor: context.isDark ? _sandColorDark : _sandColorLight,
            ),
          ),
        );
      },
    );
  }
}

/// One side wall of a chamber, expressed as a quadratic bezier so the sand
/// polygons below can solve for "where does this wall cross a given Y" and
/// trace along it — the sand then hugs the glass exactly at any fill level.
class _BezierWall {
  const _BezierWall(this.p0, this.c, this.p1);

  final Offset p0;
  final Offset c;
  final Offset p1;

  Offset pointAt(double t) {
    final double mt = 1 - t;
    return Offset(
      mt * mt * p0.dx + 2 * mt * t * c.dx + t * t * p1.dx,
      mt * mt * p0.dy + 2 * mt * t * c.dy + t * t * p1.dy,
    );
  }

  /// Solves for the parameter t at which this (y-monotonic) wall crosses
  /// [targetY].
  double tAtY(double targetY) {
    final double a = p0.dy - 2 * c.dy + p1.dy;
    final double b = 2 * (c.dy - p0.dy);
    final double cc = p0.dy - targetY;
    if (a.abs() < 1e-6) {
      return b.abs() < 1e-6 ? 0 : (-cc / b).clamp(0.0, 1.0);
    }
    final double disc = b * b - 4 * a * cc;
    if (disc < 0) return 0;
    final double sqrtDisc = sqrt(disc);
    final double t1 = (-b + sqrtDisc) / (2 * a);
    final double t2 = (-b - sqrtDisc) / (2 * a);
    if (t1 >= 0 && t1 <= 1) return t1;
    if (t2 >= 0 && t2 <= 1) return t2;
    return t1.clamp(0.0, 1.0);
  }

  /// Walks this wall from [tStart] to [tEnd] in [steps] line segments.
  List<Offset> trace(double tStart, double tEnd, int steps) {
    return List.generate(steps + 1, (i) => pointAt(tStart + (tEnd - tStart) * i / steps));
  }
}

class _HourglassPainter extends CustomPainter {
  _HourglassPainter({required this.progress, required this.edgeColor, required this.sandColor});

  /// 0 → top chamber full / bottom empty, 1 → top chamber empty / bottom full.
  final double progress;
  final Color edgeColor;
  final Color sandColor;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// The upper chamber's remaining sand — hugs the wall curves exactly and
  /// domes slightly at the surface as it drains.
  static Path _topSandPath(
    _BezierWall leftWall,
    _BezierWall rightWall,
    double topY,
    double midY,
    double progress,
  ) {
    final double surfaceY = _lerp(topY, midY, progress);
    if (surfaceY >= midY) return Path();

    final List<Offset> leftSide = leftWall.trace(0, leftWall.tAtY(surfaceY), 12); // neck → surface
    final List<Offset> rightSide = rightWall.trace(rightWall.tAtY(surfaceY), 1, 12); // surface → neck

    final Path path = Path()..moveTo(leftSide.first.dx, leftSide.first.dy);
    for (final Offset p in leftSide.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final Offset leftSurface = leftSide.last;
    final Offset rightSurface = rightSide.first;
    final double dome = (rightSurface.dx - leftSurface.dx).abs() * 0.06;
    path.quadraticBezierTo(
      (leftSurface.dx + rightSurface.dx) / 2,
      surfaceY + dome,
      rightSurface.dx,
      rightSurface.dy,
    );
    for (final Offset p in rightSide.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path..close(); // close() draws the final neck-crossing edge.
  }

  /// The lower chamber's accumulated sand — mirrors [_topSandPath], piling
  /// up from the bottom cap toward the neck as [progress] grows.
  static Path _bottomSandPath(
    _BezierWall leftWall,
    _BezierWall rightWall,
    double bottomY,
    double midY,
    double progress,
  ) {
    final double surfaceY = _lerp(bottomY, midY, progress);
    if (surfaceY <= midY) return Path();

    final List<Offset> leftSide = leftWall.trace(0, leftWall.tAtY(surfaceY), 12); // bottom → surface
    final List<Offset> rightSide = rightWall.trace(1, rightWall.tAtY(surfaceY), 12); // bottom → surface

    final Path path = Path()..moveTo(leftSide.first.dx, leftSide.first.dy);
    for (final Offset p in leftSide.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final Offset leftSurface = leftSide.last;
    final Offset rightSurface = rightSide.last;
    final double dome = (rightSurface.dx - leftSurface.dx).abs() * 0.06;
    path.quadraticBezierTo(
      (leftSurface.dx + rightSurface.dx) / 2,
      surfaceY - dome,
      rightSurface.dx,
      rightSurface.dy,
    );
    for (final Offset p in rightSide.reversed.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path..close(); // close() draws the final bottom-cap edge.
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double left = w * 0.15;
    final double right = w - w * 0.15;
    final double topY = h * 0.14;
    final double bottomY = h - h * 0.14;
    final double midY = h / 2;
    final double neckHalf = w * 0.045;
    final double neckLeft = w / 2 - neckHalf;
    final double neckRight = w / 2 + neckHalf;

    // Control points are pushed outward past the cap edges (not pinned to
    // them), so each wall bulges to a wide midpoint before tapering into the
    // neck — a rounded hourglass bulb instead of a straight-sided pot.
    final double bulge = w * 0.14;
    final _BezierWall topLeftWall = _BezierWall(
      Offset(neckLeft, midY),
      Offset(left - bulge, (midY + topY) / 2),
      Offset(left, topY),
    );
    final _BezierWall topRightWall = _BezierWall(
      Offset(right, topY),
      Offset(right + bulge, (topY + midY) / 2),
      Offset(neckRight, midY),
    );
    final _BezierWall bottomLeftWall = _BezierWall(
      Offset(left, bottomY),
      Offset(left - bulge, (bottomY + midY) / 2),
      Offset(neckLeft, midY),
    );
    final _BezierWall bottomRightWall = _BezierWall(
      Offset(neckRight, midY),
      Offset(right + bulge, (midY + bottomY) / 2),
      Offset(right, bottomY),
    );

    // 1. Glass outline — two quadratic-bezier half-bulbs meeting at the neck.
    final Path glassPath = Path()
      ..moveTo(left, topY)
      ..lineTo(right, topY)
      ..quadraticBezierTo(topRightWall.c.dx, topRightWall.c.dy, topRightWall.p1.dx, topRightWall.p1.dy)
      ..quadraticBezierTo(bottomRightWall.c.dx, bottomRightWall.c.dy, bottomRightWall.p1.dx, bottomRightWall.p1.dy)
      ..lineTo(left, bottomY)
      ..quadraticBezierTo(bottomLeftWall.c.dx, bottomLeftWall.c.dy, bottomLeftWall.p1.dx, bottomLeftWall.p1.dy)
      ..quadraticBezierTo(topLeftWall.c.dx, topLeftWall.c.dy, topLeftWall.p1.dx, topLeftWall.p1.dy)
      ..close();
    canvas.drawPath(
      glassPath,
      Paint()
        ..color = edgeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.016
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // 2. Top and bottom caps — small filled rounded rects at full color.
    final double capThickness = h * 0.07;
    final Paint capPaint = Paint()..color = edgeColor;
    final Radius capRadius = Radius.circular(capThickness / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left, topY - capThickness / 2, right - left, capThickness), capRadius),
      capPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, bottomY - capThickness / 2, right - left, capThickness),
        capRadius,
      ),
      capPaint,
    );

    // 3 & 4. Top (draining) and bottom (accumulating) sand, hugging the
    // glass walls exactly at the current fill level.
    final Paint sandPaint = Paint()..color = sandColor;
    canvas.drawPath(_topSandPath(topLeftWall, topRightWall, topY, midY, progress), sandPaint);
    canvas.drawPath(_bottomSandPath(bottomLeftWall, bottomRightWall, bottomY, midY, progress), sandPaint);

    // 5. Sand stream through the neck, wobbling slightly for a trickling
    // look, and stopping right at the current bottom sand surface.
    if (progress > 0.02 && progress < 0.95) {
      final double bottomSurfaceY = _lerp(bottomY, midY, progress);
      final double wobble = sin(progress * pi * 8) * w * 0.01;
      canvas.drawLine(
        Offset(w / 2 + wobble, midY),
        Offset(w / 2 + wobble, bottomSurfaceY),
        Paint()
          ..color = sandColor.withValues(alpha: 0.85)
          ..strokeWidth = w * 0.014
          ..strokeCap = StrokeCap.round,
      );
    }

    // 6. Falling particles — a few grains riding the stream down, with a
    // fixed seed so their horizontal jitter stays stable frame to frame.
    if (progress > 0.05 && progress < 0.9) {
      final Random rnd = Random(42);
      final double bottomSurfaceY = _lerp(bottomY, midY, progress);
      for (int i = 0; i < 3; i++) {
        final double jitterX = (rnd.nextDouble() - 0.5) * w * 0.03;
        final double yT = (progress * 7 + i * 0.33) % 1.0;
        canvas.drawCircle(
          Offset(w / 2 + jitterX, _lerp(midY, bottomSurfaceY, yT)),
          w * 0.012,
          Paint()..color = sandColor.withValues(alpha: 0.7),
        );
      }
    }
  }

  // 7. Only progress or color changes warrant a repaint.
  @override
  bool shouldRepaint(covariant _HourglassPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.edgeColor != edgeColor ||
      oldDelegate.sandColor != sandColor;
}
