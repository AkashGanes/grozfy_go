import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {

  // ── Blob controllers ──────────────────────────────────────────────────────
  late final AnimationController _blob1Ctrl;
  late final AnimationController _blob2Ctrl;
  late final AnimationController _blob3Ctrl;
  late final Animation<double> _blob1Anim;
  late final Animation<double> _blob2Anim;
  late final Animation<double> _blob3Anim;

  // ── Ring rotation controllers ─────────────────────────────────────────────
  late final AnimationController _ring1Ctrl;
  late final AnimationController _ring2Ctrl;

  // ── Scatter dot controllers ───────────────────────────────────────────────
  late final List<AnimationController> _dotCtrls;
  late final List<Animation<double>> _dotAnims;

  // ── Logo rock + float ─────────────────────────────────────────────────────
  late final AnimationController _rockCtrl;
  late final Animation<double> _rockAnim;
  late final Animation<double> _floatAnim;

  // ── Shadow pulse ──────────────────────────────────────────────────────────
  late final AnimationController _shadowCtrl;
  late final Animation<double> _shadowAnim;

  // ── Entry animations ──────────────────────────────────────────────────────
  late final AnimationController _logoEntryCtrl;
  late final AnimationController _textEntryCtrl;
  late final AnimationController _chipsEntryCtrl;
  late final AnimationController _loaderEntryCtrl;
  late final Animation<double> _logoEntryScale;
  late final Animation<double> _logoEntryOpacity;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _textOpacity;
  late final Animation<Offset> _chipsSlide;
  late final Animation<double> _chipsOpacity;
  late final Animation<Offset> _loaderSlide;
  late final Animation<double> _loaderOpacity;

  // ── Progress bar ──────────────────────────────────────────────────────────
  late final AnimationController _progressCtrl;
  late final Animation<double> _progressAnim;

  static const _dotDelays    = [200, 700, 1100, 400, 1600, 2000];
  static const _dotDurations = [3200, 4000, 4200, 3500, 3000, 3200];

  @override
  void initState() {
    super.initState();
    _initBlobs();
    _initRings();
    _initDots();
    _initLogoAnimation();
    _initEntryAnimations();
    _initProgress();
    _startBootstrap();
  }

  void _initBlobs() {
    _blob1Ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 5000))
      ..repeat(reverse: true);
    _blob2Ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 6000));
    _blob3Ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4500));

    _blob1Anim = Tween(begin: 1.0, end: 1.08)
        .animate(CurvedAnimation(parent: _blob1Ctrl, curve: Curves.easeInOut));
    _blob2Anim = Tween(begin: 1.0, end: 1.08)
        .animate(CurvedAnimation(parent: _blob2Ctrl, curve: Curves.easeInOut));
    _blob3Anim = Tween(begin: 1.0, end: 1.08)
        .animate(CurvedAnimation(parent: _blob3Ctrl, curve: Curves.easeInOut));

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) { _blob2Ctrl.repeat(reverse: true); }
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) { _blob3Ctrl.repeat(reverse: true); }
    });
  }

  void _initRings() {
    _ring1Ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 20000))
      ..repeat();
    _ring2Ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 14000))
      ..repeat();
  }

  void _initDots() {
    _dotCtrls = List.generate(
      6,
      (i) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _dotDurations[i]),
      ),
    );
    _dotAnims = _dotCtrls
        .map((c) => Tween(begin: 1.0, end: 1.6)
            .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)))
        .toList();

    for (int i = 0; i < 6; i++) {
      Future.delayed(Duration(milliseconds: _dotDelays[i]), () {
        if (mounted) { _dotCtrls[i].repeat(reverse: true); }
      });
    }
  }

  void _initLogoAnimation() {
    _rockCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3500))
      ..repeat(reverse: true);
    _rockAnim = Tween(begin: -2.0, end: 2.0)
        .animate(CurvedAnimation(parent: _rockCtrl, curve: Curves.easeInOut));
    _floatAnim = Tween(begin: 0.0, end: -3.0)
        .animate(CurvedAnimation(parent: _rockCtrl, curve: Curves.easeInOut));

    _shadowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat(reverse: true);
    _shadowAnim = Tween(begin: 1.0, end: 1.2)
        .animate(CurvedAnimation(parent: _shadowCtrl, curve: Curves.easeInOut));
  }

  void _initEntryAnimations() {
    _logoEntryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _logoEntryScale = Tween(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(
            parent: _logoEntryCtrl,
            curve: const Cubic(0.34, 1.56, 0.64, 1)));
    _logoEntryOpacity = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _logoEntryCtrl,
            curve: const Interval(0.0, 0.6, curve: Curves.easeOut)));

    _textEntryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _textSlide =
        Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _textEntryCtrl,
                curve: const Cubic(0.34, 1.4, 0.64, 1)));
    _textOpacity = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _textEntryCtrl, curve: Curves.easeOut));

    _chipsEntryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _chipsSlide =
        Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(
            CurvedAnimation(parent: _chipsEntryCtrl, curve: Curves.easeOut));
    _chipsOpacity = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _chipsEntryCtrl, curve: Curves.easeOut));

    _loaderEntryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _loaderSlide =
        Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(
            CurvedAnimation(parent: _loaderEntryCtrl, curve: Curves.easeOut));
    _loaderOpacity = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _loaderEntryCtrl, curve: Curves.easeOut));

    _logoEntryCtrl.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) { _textEntryCtrl.forward(); }
    });
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) { _chipsEntryCtrl.forward(); }
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) { _loaderEntryCtrl.forward(); }
    });
  }

  void _initProgress() {
    _progressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500));
    _progressAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.68), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 0.68, end: 0.85), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.0), weight: 20),
    ]).animate(
        CurvedAnimation(parent: _progressCtrl, curve: Curves.easeInOut));

    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) { _progressCtrl.forward(); }
    });
  }

  void _startBootstrap() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = ref.read(appControllerProvider);
      if (!app.bootstrapped) {
        await app.bootstrap();
      }

      if (!mounted) return;

      await Future.delayed(const Duration(milliseconds: 350));

      if (!mounted) return;

      final String route;
      if (app.languageCode.isEmpty) {
        route = AppRoutes.language;
      } else if (app.isLoggedIn) {
        if (!app.profileCompleted) {
          route = AppRoutes.register;
        } else if (!app.isKycComplete) {
          route = AppRoutes.kycDocuments;
        } else if (!app.hasSelectedLocation) {
          route = AppRoutes.currentLocation;
        } else {
          route = AppRoutes.dashboard;
        }
      } else {
        route = AppRoutes.login;
      }

      Navigator.of(context).pushReplacementNamed(route);
    });
  }

  @override
  void dispose() {
    _blob1Ctrl.dispose();
    _blob2Ctrl.dispose();
    _blob3Ctrl.dispose();
    _ring1Ctrl.dispose();
    _ring2Ctrl.dispose();
    for (final c in _dotCtrls) {
      c.dispose();
    }
    _rockCtrl.dispose();
    _shadowCtrl.dispose();
    _logoEntryCtrl.dispose();
    _textEntryCtrl.dispose();
    _chipsEntryCtrl.dispose();
    _loaderEntryCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8EE),
      body: Stack(
        children: [
          _Background(),
          _AnimatedBlobs(
              blob1: _blob1Anim, blob2: _blob2Anim, blob3: _blob3Anim),
          _ScatterDots(anims: _dotAnims),
          _RotatingRings(ring1: _ring1Ctrl, ring2: _ring2Ctrl),
          _MainContent(
            logoEntryScale: _logoEntryScale,
            logoEntryOpacity: _logoEntryOpacity,
            rockAnim: _rockAnim,
            floatAnim: _floatAnim,
            shadowAnim: _shadowAnim,
            textSlide: _textSlide,
            textOpacity: _textOpacity,
            chipsSlide: _chipsSlide,
            chipsOpacity: _chipsOpacity,
          ),
          _BottomLoader(
            slideAnim: _loaderSlide,
            opacityAnim: _loaderOpacity,
            progressAnim: _progressAnim,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background
// ─────────────────────────────────────────────────────────────────────────────

class _Background extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFDF7), Color(0xFFFFF4E0), Color(0xFFFFF0F5)],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated Blobs
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedBlobs extends StatelessWidget {
  final Animation<double> blob1, blob2, blob3;
  const _AnimatedBlobs(
      {required this.blob1, required this.blob2, required this.blob3});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Top-right — amber/orange
        Positioned(
          top: -80,
          right: -80,
          child: ScaleTransition(
            scale: blob1,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFFFFD97D).withValues(alpha: .33),
                  const Color(0xFFFFB300).withValues(alpha: .13),
                ]),
              ),
            ),
          ),
        ),
        // Bottom-left — green
        Positioned(
          bottom: -60,
          left: -60,
          child: ScaleTransition(
            scale: blob2,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFFB5F5D5).withValues(alpha: .33),
                  const Color(0xFF00C97A).withValues(alpha: .11),
                ]),
              ),
            ),
          ),
        ),
        // Mid-right — pink
        Positioned(
          top: MediaQuery.of(context).size.height * 0.5,
          right: -30,
          child: ScaleTransition(
            scale: blob3,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFFFFB3C6).withValues(alpha: .33),
                  const Color(0xFFFF5C8A).withValues(alpha: .11),
                ]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scatter Dots
// ─────────────────────────────────────────────────────────────────────────────

class _DotData {
  final double topFraction;
  final double? leftFraction;
  final double? rightFraction;
  final Color color;
  final double size;

  const _DotData({
    required this.topFraction,
    this.leftFraction,
    this.rightFraction,
    required this.color,
    required this.size,
  });
}

const _dots = [
  _DotData(topFraction: .12, leftFraction: .14,  color: Color(0xFFFFB300), size: 8),
  _DotData(topFraction: .18, rightFraction: .18, color: Color(0xFFFF5C8A), size: 6),
  _DotData(topFraction: .72, leftFraction: .20,  color: Color(0xFF00C97A), size: 5),
  _DotData(topFraction: .78, rightFraction: .16, color: Color(0xFFFFB300), size: 7),
  _DotData(topFraction: .40, leftFraction: .08,  color: Color(0xFFFF5C8A), size: 5),
  _DotData(topFraction: .35, rightFraction: .09, color: Color(0xFF00C97A), size: 6),
];

class _ScatterDots extends StatelessWidget {
  final List<Animation<double>> anims;
  const _ScatterDots({required this.anims});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Stack(
      children: List.generate(_dots.length, (i) {
        final d = _dots[i];
        return Positioned(
          top: size.height * d.topFraction,
          left: d.leftFraction != null ? size.width * d.leftFraction! : null,
          right:
              d.rightFraction != null ? size.width * d.rightFraction! : null,
          child: ScaleTransition(
            scale: anims[i],
            child: Container(
              width: d.size,
              height: d.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: d.color.withValues(alpha: .6),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rotating Dashed Rings
// ─────────────────────────────────────────────────────────────────────────────

class _DashedRingPainter extends CustomPainter {
  final Color color;
  final double dashLength;
  final double gapLength;

  _DashedRingPainter({
    required this.color,
    required this.dashLength,
    required this.gapLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final totalDash = dashLength + gapLength;
    final count = (2 * pi * radius / totalDash).floor();

    for (int i = 0; i < count; i++) {
      final startAngle = i * totalDash / radius;
      final sweepAngle = dashLength / radius;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => false;
}

class _RotatingRings extends StatelessWidget {
  final AnimationController ring1, ring2;
  const _RotatingRings({required this.ring1, required this.ring2});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.15),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring — amber, clockwise
          RotationTransition(
            turns: ring1,
            child: CustomPaint(
              size: const Size(320, 320),
              painter: _DashedRingPainter(
                color: const Color(0xFFFFB300).withValues(alpha: .25),
                dashLength: 6,
                gapLength: 5,
              ),
            ),
          ),
          // Inner ring — green, counter-clockwise
          RotationTransition(
            turns: Tween(begin: 1.0, end: 0.0).animate(ring2),
            child: CustomPaint(
              size: const Size(260, 260),
              painter: _DashedRingPainter(
                color: const Color(0xFF00C97A).withValues(alpha: .2),
                dashLength: 6,
                gapLength: 5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Content
// ─────────────────────────────────────────────────────────────────────────────

class _MainContent extends StatelessWidget {
  final Animation<double> logoEntryScale, logoEntryOpacity;
  final Animation<double> rockAnim, floatAnim, shadowAnim;
  final Animation<Offset> textSlide, chipsSlide;
  final Animation<double> textOpacity, chipsOpacity;

  const _MainContent({
    required this.logoEntryScale,
    required this.logoEntryOpacity,
    required this.rockAnim,
    required this.floatAnim,
    required this.shadowAnim,
    required this.textSlide,
    required this.textOpacity,
    required this.chipsSlide,
    required this.chipsOpacity,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: logoEntryOpacity,
            child: ScaleTransition(
              scale: logoEntryScale,
              child: _LogoCard(
                rockAnim: rockAnim,
                floatAnim: floatAnim,
                shadowAnim: shadowAnim,
              ),
            ),
          ),
          const SizedBox(height: 32),
          FadeTransition(
            opacity: textOpacity,
            child: SlideTransition(
              position: textSlide,
              child: _TextBlock(),
            ),
          ),
          const SizedBox(height: 18),
          FadeTransition(
            opacity: chipsOpacity,
            child: SlideTransition(
              position: chipsSlide,
              child: _ChipsRow(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Logo Card
// ─────────────────────────────────────────────────────────────────────────────

class _LogoCard extends StatelessWidget {
  final Animation<double> rockAnim, floatAnim, shadowAnim;
  const _LogoCard({
    required this.rockAnim,
    required this.floatAnim,
    required this.shadowAnim,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 172,
      height: 172,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Pulsing elliptical shadow beneath card
          Positioned(
            bottom: -16,
            child: ScaleTransition(
              scale: shadowAnim,
              child: Container(
                width: 110,
                height: 18,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: const Color(0xFFFFA000).withValues(alpha: .22),
                ),
              ),
            ),
          ),
          // Rocking logo card
          AnimatedBuilder(
            animation: Listenable.merge([rockAnim, floatAnim]),
            builder: (context, child) => Transform.translate(
              offset: Offset(0, floatAnim.value),
              child: Transform.rotate(
                angle: rockAnim.value * pi / 180,
                child: child,
              ),
            ),
            child: Container(
              width: 152,
              height: 152,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(36),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF8C00).withValues(alpha: .18),
                    blurRadius: 60,
                    offset: const Offset(0, 20),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 116,
                  height: 116,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          // "Go" badge — top right
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFB300), Color(0xFFFF7A00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF8C00).withValues(alpha: .4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'Go',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Text Block
// ─────────────────────────────────────────────────────────────────────────────

class _TextBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RichText(
          text: TextSpan(
            style: GoogleFonts.nunito(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: const Color(0xFF1C1C1C),
            ),
            children: [
              const TextSpan(text: 'Grozfy '),
              TextSpan(
                text: 'Go',
                style: GoogleFonts.nunito(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  foreground: Paint()
                    ..shader = const LinearGradient(
                      colors: [Color(0xFFFF7A00), Color(0xFFFFB300)],
                    ).createShader(const Rect.fromLTWH(0, 0, 90, 50)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Fast deliveries. Strong earnings.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12.5,
            color: Colors.black.withValues(alpha: .38),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chips Row
// ─────────────────────────────────────────────────────────────────────────────

class _ChipsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SplashChip(
          label: 'Fast Delivery',
          dotColor: const Color(0xFFFF9500),
          bg: const Color(0xFFFFF3D6),
          textColor: const Color(0xFFB36A00),
        ),
        const SizedBox(width: 8),
        _SplashChip(
          label: 'Earn More',
          dotColor: const Color(0xFF00C97A),
          bg: const Color(0xFFE6FBF2),
          textColor: const Color(0xFF007A47),
        ),
      ],
    );
  }
}

class _SplashChip extends StatelessWidget {
  final String label;
  final Color dotColor, bg, textColor;
  const _SplashChip({
    required this.label,
    required this.dotColor,
    required this.bg,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
              letterSpacing: .2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Loader
// ─────────────────────────────────────────────────────────────────────────────

class _BottomLoader extends StatelessWidget {
  final Animation<Offset> slideAnim;
  final Animation<double> opacityAnim, progressAnim;

  const _BottomLoader({
    required this.slideAnim,
    required this.opacityAnim,
    required this.progressAnim,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 52,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: opacityAnim,
        child: SlideTransition(
          position: slideAnim,
          child: Column(
            children: [
              Container(
                width: 100,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: AnimatedBuilder(
                  animation: progressAnim,
                  builder: (context, _) => FractionallySizedBox(
                    widthFactor: progressAnim.value,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF7A00), Color(0xFFFFB300)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'STARTING UP',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: Colors.black.withValues(alpha: .22),
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
