import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_theme.dart';

class _SplashLoader extends StatelessWidget {
  const _SplashLoader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 4,
      decoration: BoxDecoration(
        color: AppTheme.mango.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(
          duration: 800.ms,
          color: AppTheme.mango.withValues(alpha: 0.6),
        );
  }
}

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final app = ref.read(appControllerProvider);
    if (!app.bootstrapped) {
      await app.bootstrap();
    }

    if (!mounted) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));

    if (!mounted) {
      return;
    }

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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF102138), Color(0xFF1D4E80), Color(0xFF33BFAE)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: Tween<double>(
                  begin: 0.94,
                  end: 1.05,
                ).animate(_controller),
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Image(
                    image: AssetImage('assets/images/logo.png'),
                    width: 56,
                    height: 56,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Grozfy Go',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Fast deliveries. Strong earnings.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 34),
              const SizedBox(
                width: 28,
                height: 28,
                child: _SplashLoader(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
