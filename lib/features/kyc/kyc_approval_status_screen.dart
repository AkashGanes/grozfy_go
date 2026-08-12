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
        appBar: AppBar(
          toolbarHeight: 64,
          title: const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('KYC Verification'),
            ),
          ),
          centerTitle: true,
          backgroundColor: context.surface,
          elevation: 0,
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: switch (phase) {
            _Phase.pending => _MinimalStatusView(
              key: const ValueKey('pending'),
              iconOverride: const _HourglassSandIcon(size: 168),
              title: 'Verification Pending',
              subtitle: "We're reviewing your documents. This may take above 24 hours.",
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
              icon: Icons.verified_rounded,
              iconColor: context.success,
              iconContainerColor: context.successContainer,
              containerSize: 116,
              iconSize: 78,
              richGlow: true,
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
    this.containerSize = 96,
    this.iconSize = 48,
    this.richGlow = false,
    required this.title,
    required this.subtitle,
    this.extra,
    this.actions = const [],
  });

  final IconData? icon;
  final Color? iconColor;
  final Color? iconContainerColor;
  final Widget? iconOverride;
  final double containerSize;
  final double iconSize;
  final bool richGlow;
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
        width: containerSize,
        height: containerSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: iconContainerColor,
          shape: BoxShape.circle,
          boxShadow: richGlow
              ? [
                  BoxShadow(
                    color: (iconColor ?? context.textPrimary).withValues(alpha: 0.22),
                    blurRadius: 24,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Icon(icon, size: iconSize, color: iconColor),
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
                style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 14.5,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.15,
                ),
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

/// A modern, minimal vector-style hourglass whose sand drains from the top
/// chamber into the bottom one over [_cycleDuration], then does one quick
/// 180° flip in the last 8% of the cycle so the sand can start draining
/// again. Its brand blue is fixed — deliberately independent of the current
/// theme — while the thin glass outline adapts for contrast. Owns its own
/// [AnimationController], so the animation stops automatically the moment
/// this widget is disposed (e.g. when the phase switches away from pending).
class _HourglassSandIcon extends StatefulWidget {
  const _HourglassSandIcon({this.size = 160});

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
  // Fixed brand blue — must read identically in every theme, so it never
  // comes from context_colors/Theme.of.
  static const Color _mainBlue = Color(0xFF3B8EF3);
  static const Color _lightBlue = Color(0xFF8FC6FF);
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
            size: Size(widget.size, widget.size * 1.15),
            painter: _HourglassPainter(
              progress: progress,
              mainColor: _mainBlue,
              lightColor: _lightBlue,
              // Same token + weight as the OutlinedButton's default border
              // (colorScheme.outline, 1 logical pixel), for an exact match.
              outlineColor: context.borderStrong,
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
  _HourglassPainter({
    required this.progress,
    required this.mainColor,
    required this.lightColor,
    required this.outlineColor,
  });

  /// 0 → top chamber full / bottom empty, 1 → top chamber empty / bottom full.
  final double progress;
  final Color mainColor;
  final Color lightColor;
  final Color outlineColor;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// A handful of small, fixed decorative dots and plus-marks scattered just
  /// outside the glass silhouette — purely ornamental, deliberately placed
  /// rather than randomly scattered, for a clean modern-illustration feel.
  static const List<Offset> _dotSpots = [
    Offset(0.06, 0.1),
    Offset(0.94, 0.18),
    Offset(0.1, 0.85),
    Offset(0.9, 0.78),
  ];
  static const List<Offset> _plusSpots = [Offset(0.88, 0.42), Offset(0.14, 0.56)];

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

    final Offset center = Offset(w / 2, h / 2);

    // 0. Soft blue glow behind everything — lightweight (a single blurred
    // circle), not a full illustration backdrop.
    canvas.drawCircle(
      center,
      w * 0.62,
      Paint()
        ..color = mainColor.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );

    // A few very subtle decorative dots and plus-marks around the glass,
    // fixed in place rather than randomly scattered, for a deliberate,
    // premium illustration feel.
    final Paint decorPaint = Paint()..color = mainColor.withValues(alpha: 0.28);
    for (final Offset spot in _dotSpots) {
      canvas.drawCircle(Offset(spot.dx * w, spot.dy * h), w * 0.014, decorPaint);
    }
    for (final Offset spot in _plusSpots) {
      final Offset c = Offset(spot.dx * w, spot.dy * h);
      final double armLen = w * 0.022;
      final Paint plusPaint = Paint()
        ..color = mainColor.withValues(alpha: 0.28)
        ..strokeWidth = w * 0.008
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(c.dx - armLen, c.dy), Offset(c.dx + armLen, c.dy), plusPaint);
      canvas.drawLine(Offset(c.dx, c.dy - armLen), Offset(c.dx, c.dy + armLen), plusPaint);
    }

    // 1. Glass outline — two quadratic-bezier half-bulbs meeting at the
    // neck, thin and mostly transparent so the body reads as clean glass.
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
        ..color = outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // 2. Top and bottom bars — rounded, filled with the brand blue with a
    // subtle lighter-blue gradient for depth.
    final double capThickness = h * 0.06;
    final Radius capRadius = Radius.circular(capThickness / 2);
    final double capOverhang = w * 0.035;
    final double capLeft = left - capOverhang;
    final double capRight = right + capOverhang;
    final Rect topBarRect = Rect.fromLTWH(capLeft, topY - capThickness / 2, capRight - capLeft, capThickness);
    final Rect bottomBarRect = Rect.fromLTWH(capLeft, bottomY - capThickness / 2, capRight - capLeft, capThickness);
    final Paint topBarPaint = Paint()
      ..shader = LinearGradient(
        colors: [lightColor, mainColor],
      ).createShader(topBarRect);
    final Paint bottomBarPaint = Paint()
      ..shader = LinearGradient(
        colors: [mainColor, lightColor],
      ).createShader(bottomBarRect);
    canvas.drawRRect(RRect.fromRectAndRadius(topBarRect, capRadius), topBarPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(bottomBarRect, capRadius), bottomBarPaint);

    // 3 & 4. Top (draining) and bottom (accumulating) sand, hugging the
    // glass walls exactly at the current fill level, with a light-to-main
    // blue gradient for a touch of depth.
    final Path topSand = _topSandPath(topLeftWall, topRightWall, topY, midY, progress);
    final Path bottomSand = _bottomSandPath(bottomLeftWall, bottomRightWall, bottomY, midY, progress);
    final Paint sandPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [lightColor, mainColor],
      ).createShader(Rect.fromLTWH(left, topY, right - left, bottomY - topY));
    canvas.drawPath(topSand, sandPaint);
    canvas.drawPath(bottomSand, sandPaint);

    // 5. A dotted stream through the neck — small evenly-spaced dots rather
    // than a solid line — stopping right at the current bottom sand surface.
    if (progress > 0.02 && progress < 0.95) {
      final double bottomSurfaceY = _lerp(bottomY, midY, progress);
      const int dotCount = 6;
      for (int i = 0; i < dotCount; i++) {
        final double dotT = ((progress * 3) + i / dotCount) % 1.0;
        canvas.drawCircle(
          Offset(w / 2, _lerp(midY, bottomSurfaceY, dotT)),
          w * 0.009,
          Paint()..color = mainColor.withValues(alpha: 0.8),
        );
      }
    }
  }

  // 6. Only progress or color changes warrant a repaint.
  @override
  bool shouldRepaint(covariant _HourglassPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.mainColor != mainColor ||
      oldDelegate.lightColor != lightColor ||
      oldDelegate.outlineColor != outlineColor;
}
