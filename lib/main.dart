import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/navigation/app_routes.dart';
import 'core/state/providers.dart';
import 'core/state/app_scope.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/kyc/bank_setup_screen.dart';
import 'features/kyc/kyc_documents_screen.dart';
import 'features/kyc/vehicle_details_screen.dart';
import 'features/language/language_selection_screen.dart';
import 'features/location/current_location_picker_screen.dart';
import 'features/location/location_tracking_screen.dart';
import 'features/orders/navigation_screen.dart';
import 'features/orders/order_details_screen.dart';
import 'features/orders/order_request_screen.dart';
import 'features/orders/order_status_screen.dart';
import 'features/permissions/location_permission_screen.dart';
import 'features/splash/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: DeliveryPartnerApp()));
}

class DeliveryPartnerApp extends ConsumerStatefulWidget {
  const DeliveryPartnerApp({super.key});

  @override
  ConsumerState<DeliveryPartnerApp> createState() => _DeliveryPartnerAppState();
}

class _DeliveryPartnerAppState extends ConsumerState<DeliveryPartnerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appControllerProvider.notifier).initializeConnectivity();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appControllerProvider.notifier).setFirstFrameBuilt(true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      ref.read(appControllerProvider.notifier).setAppResumed(true);
      ref.read(appControllerProvider.notifier).checkConnectivity();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      ref.read(appControllerProvider.notifier).setAppResumed(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    return AppScope(
      controller: controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'FlowFleet Partner',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        initialRoute: AppRoutes.splash,
        builder: (context, child) {
          return NoInternetWrapper(child: child ?? const SizedBox.shrink());
        },
        onGenerateRoute: (RouteSettings settings) {
          switch (settings.name) {
            case AppRoutes.splash:
              return MaterialPageRoute<void>(
                builder: (_) => const SplashScreen(),
              );
            case AppRoutes.language:
              return MaterialPageRoute<void>(
                builder: (_) => const LanguageSelectionScreen(),
              );
            case AppRoutes.login:
              return MaterialPageRoute<void>(
                builder: (_) => const LoginScreen(),
              );
            case AppRoutes.register:
              return MaterialPageRoute<void>(
                builder: (_) => const RegisterScreen(),
              );
            case AppRoutes.kycDocuments:
              return MaterialPageRoute<void>(
                builder: (_) => const KycDocumentsScreen(),
              );
            case AppRoutes.vehicleDetails:
              return MaterialPageRoute<void>(
                builder: (_) => const VehicleDetailsScreen(),
              );
            case AppRoutes.bankSetup:
              return MaterialPageRoute<void>(
                builder: (_) => const BankSetupScreen(),
              );
            case AppRoutes.permission:
              return MaterialPageRoute<void>(
                builder: (_) => const LocationPermissionScreen(),
              );
            case AppRoutes.tracking:
              return MaterialPageRoute<void>(
                builder: (_) => const LocationTrackingScreen(),
              );
            case AppRoutes.currentLocation:
              return MaterialPageRoute<void>(
                builder: (_) => const CurrentLocationPickerScreen(),
              );
            case AppRoutes.orderRequest:
              return MaterialPageRoute<void>(
                builder: (_) => const OrderRequestScreen(),
              );
            case AppRoutes.orderDetails:
              return MaterialPageRoute<void>(
                builder: (_) => const OrderDetailsScreen(),
              );
            case AppRoutes.navigation:
              return MaterialPageRoute<void>(
                builder: (_) => const NavigationScreen(),
              );
            case AppRoutes.orderStatus:
              return MaterialPageRoute<void>(
                builder: (_) => const OrderStatusScreen(),
              );
            case AppRoutes.dashboard:
              return MaterialPageRoute<void>(
                builder: (_) => const DashboardScreen(),
              );
            default:
              return MaterialPageRoute<void>(
                builder: (_) => const SplashScreen(),
              );
          }
        },
      ),
    );
  }
}

class NoInternetWrapper extends ConsumerWidget {
  const NoInternetWrapper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final showOverlay = controller.showNoInternetOverlay;
    final showRetry = controller.showRetryButton;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        alignment: Alignment.center,
        children: [
          child,
          if (showOverlay)
            Positioned.fill(
              child: NoInternetOverlayWithRetry(
                showRetryButton: showRetry,
                onRetry: () {
                  ref.read(appControllerProvider.notifier).retryConnection();
                },
              ),
            ),
        ],
      ),
    );
  }
}

class NoInternetOverlayWithRetry extends StatefulWidget {
  const NoInternetOverlayWithRetry({
    super.key,
    required this.showRetryButton,
    required this.onRetry,
  });

  final bool showRetryButton;
  final VoidCallback onRetry;

  @override
  State<NoInternetOverlayWithRetry> createState() =>
      _NoInternetOverlayWithRetryState();
}

class _NoInternetOverlayWithRetryState
    extends State<NoInternetOverlayWithRetry>
    with TickerProviderStateMixin {
  bool _isRetrying = false;
  late AnimationController _retryScaleController;
  late Animation<double> _retryScaleAnimation;

  @override
  void initState() {
    super.initState();
    _retryScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _retryScaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _retryScaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _retryScaleController.dispose();
    super.dispose();
  }

  Future<void> _handleRetry() async {
    if (_isRetrying) return;

    setState(() {
      _isRetrying = true;
    });

    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      widget.onRetry();
      setState(() {
        _isRetrying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.oceanBlue.withValues(alpha: 0.95),
            AppTheme.nightBlue.withValues(alpha: 0.98),
          ],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 40),
                const Text(
                  'Oops!',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1.2,
                    decoration: TextDecoration.none,
                    decorationColor: Colors.transparent,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No Internet Connection',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                    decorationColor: Colors.transparent,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Please check your network settings\nand try again',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    height: 1.5,
                    decoration: TextDecoration.none,
                    decorationColor: Colors.transparent,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                if (_isRetrying) ...[
                  _buildLoadingIndicator(),
                ] else if (widget.showRetryButton) ...[
                  AnimatedBuilder(
                    animation: _retryScaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _retryScaleAnimation.value,
                        child: _buildRetryButton(),
                      );
                    },
                  ),
                ] else ...[
                  _buildLoadingIndicator(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.oceanBlue),
            ),
          ),
          SizedBox(width: 8),
          Text(
            'Checking...',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.oceanBlue,
              letterSpacing: 0.5,
              decoration: TextDecoration.none,
              decorationColor: Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetryButton() {
    return GestureDetector(
      onTapDown: (_) => _retryScaleController.forward(),
      onTapUp: (_) {
        _retryScaleController.reverse();
        _handleRetry();
      },
      onTapCancel: () => _retryScaleController.reverse(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.refresh_rounded,
              color: AppTheme.oceanBlue,
              size: 18,
            ),
            SizedBox(width: 8),
            Text(
              'Retry',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.oceanBlue,
                letterSpacing: 0.5,
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
