import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/models/app_models.dart';
import 'core/localization/app_localizations.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/fcm_initializer.dart';
import 'core/services/location_ping_service.dart';
import 'core/services/offline_storage_service.dart';
import 'core/services/offline_trip_manager.dart';
import 'core/database/database_providers.dart';
import 'core/services/sync_manager.dart';
import 'core/services/timing_sync_engine.dart';
import 'core/navigation/app_routes.dart';
import 'core/security/app_lock_provider.dart';
import 'core/security/lock_screen.dart';
import 'core/state/providers.dart';
import 'core/state/app_scope.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/notifications/ui/screens/notifications_screen.dart';
import 'features/orders/my_orders_screen.dart';
import 'features/kyc/bank_setup_screen.dart';
import 'features/kyc/bank_submitted_details_screen.dart';
import 'features/kyc/kyc_documents_screen.dart';
import 'features/kyc/vehicle_details_screen.dart';
import 'features/kyc/vehicle_submitted_details_screen.dart';
import 'features/language/language_selection_screen.dart';
import 'features/location/current_location_picker_screen.dart';
import 'features/location/location_tracking_screen.dart';
import 'features/orders/navigation_screen.dart';
import 'features/orders/delivery_list_screen.dart';
import 'features/orders/delivery_tracking_screen.dart';
import 'features/orders_by_location/ui/external_delivery_trip_details_screen.dart';
import 'features/pickup_jobs/ui/pickup_pool_screen.dart';
import 'features/pickup_jobs/ui/pickup_job_detail_screen.dart';
import 'features/stats/stats_screen.dart';
import 'features/orders_by_location/ui/external_delivery_trip_list_screen.dart';
import 'features/orders_by_location/ui/orders_by_location_screen.dart';
import 'features/orders/order_details_screen.dart';
import 'features/orders/order_listing_screen.dart';
import 'features/orders/order_request_screen.dart';
import 'features/orders/order_status_screen.dart';
import 'features/orders/order_tracking_screen.dart';
import 'features/permissions/location_permission_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/security/security_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/splash/splash_screen.dart';
import 'package:device_preview/device_preview.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();

  // Offline stack: storage first (opens Hive boxes), then connectivity
  // monitoring, then sync manager (drains queues on reconnect), then trip
  // manager (prefetch helper). Order matters — sync manager subscribes to
  // connectivity, so connectivity must be running first.
  await OfflineStorageService().initialize();
  await ConnectivityService().initialize();
  ConnectivityService().startMonitoring();
  await SyncManager().initialize();
  await OfflineTripManager().initialize();
  await TimingSyncEngine().initialize(
    container.read(partnerTimingLogDaoProvider),
  );

  // Initialize Firebase
  try {
    await Firebase.initializeApp();
    // Initialize Notifications
    await FCMInitializer().init(container);
  } catch (e) {
    debugPrint(
      "⚠️ Firebase initialization failed. Make sure google-services.json is added. Error: $e",
    );
  }

  // Configure background location ping service
  await LocationPingService.initialize();

  // Load persisted security preferences before the first frame
  await container.read(appLockEnabledProvider.notifier).initialize();
  await container.read(autoLockIndexProvider.notifier).initialize();
  await container.read(biometricOnlyProvider.notifier).initialize();

  runApp(
    DevicePreview(
      enabled: false,
      builder: (context) => UncontrolledProviderScope(
        container: container,
        child: const GrozfyGoApp(),
      ),
    ),
  );
}

class GrozfyGoApp extends ConsumerStatefulWidget {
  const GrozfyGoApp({super.key});

  @override
  ConsumerState<GrozfyGoApp> createState() => _GrozfyGoAppState();
}

class _GrozfyGoAppState extends ConsumerState<GrozfyGoApp>
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
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(appControllerProvider.notifier).setAppResumed(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    return AppScope(
      controller: controller,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: controller.t('app_title'),
        theme: AppTheme.getLightTheme(
          scaffoldBackgroundColor: controller.backgroundColor,
          primaryColor: controller.accentColor,
        ),
        darkTheme: AppTheme.getDarkTheme(primaryColor: controller.accentColor),
        themeMode: controller.themeMode,
        locale: controller.languageCode.isNotEmpty
            ? Locale(controller.languageCode)
            : null,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          AppLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        initialRoute: AppRoutes.splash,
        builder: (context, child) {
          Widget content = child ?? const SizedBox.shrink();
          if (controller.isLoggedIn) {
            content = _AppLockObserver(child: content);
          }
          return NoInternetWrapper(child: content);
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
              final dynamic kycArgs = settings.arguments;
              final bool licenseReupload =
                  kycArgs is Map<String, dynamic> &&
                  kycArgs['license_reupload'] == true;
              return MaterialPageRoute<void>(
                builder: (_) =>
                    KycDocumentsScreen(licenseReuploadMode: licenseReupload),
              );
            case AppRoutes.vehicleDetails:
              final dynamic vehicleArgs = settings.arguments;
              final bool forceEdit =
                  vehicleArgs is Map<String, dynamic> &&
                  vehicleArgs['force_edit'] == true;
              final Map<String, dynamic>? submittedVehicle =
                  controller.submittedVehicleRaw;
              if (!forceEdit &&
                  submittedVehicle != null &&
                  submittedVehicle.isNotEmpty) {
                return MaterialPageRoute<void>(
                  settings: const RouteSettings(
                    name: AppRoutes.vehicleSubmittedDetails,
                  ),
                  builder: (_) => VehicleSubmittedDetailsScreen(
                    vehicleData: submittedVehicle,
                  ),
                );
              }
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const VehicleDetailsScreen(),
              );
            case AppRoutes.vehicleSubmittedDetails:
              final dynamic args = settings.arguments;
              final Map<String, dynamic> data = args is Map<String, dynamic>
                  ? args
                  : <String, dynamic>{};
              return MaterialPageRoute<void>(
                builder: (_) =>
                    VehicleSubmittedDetailsScreen(vehicleData: data),
              );
            case AppRoutes.bankSetup:
              final dynamic bankArgs = settings.arguments;
              final bool forceEdit =
                  bankArgs is Map<String, dynamic> &&
                  bankArgs['force_edit'] == true;
              final Map<String, dynamic>? submittedBank =
                  controller.submittedBankRaw;
              if (!forceEdit &&
                  submittedBank != null &&
                  submittedBank.isNotEmpty) {
                return MaterialPageRoute<void>(
                  settings: const RouteSettings(
                    name: AppRoutes.bankSubmittedDetails,
                  ),
                  builder: (_) =>
                      BankSubmittedDetailsScreen(bankData: submittedBank),
                );
              }
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const BankSetupScreen(),
              );
            case AppRoutes.bankSubmittedDetails:
              final dynamic bankArgs = settings.arguments;
              final Map<String, dynamic> bankData =
                  bankArgs is Map<String, dynamic>
                  ? bankArgs
                  : (controller.submittedBankRaw ?? <String, dynamic>{});
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => BankSubmittedDetailsScreen(bankData: bankData),
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
            case AppRoutes.orderListing:
              return MaterialPageRoute<void>(
                builder: (_) => const OrderListingScreen(),
              );
            case AppRoutes.orderRequest:
              return MaterialPageRoute<void>(
                builder: (_) => const OrderRequestScreen(),
              );
            case AppRoutes.orderDetails:
              final dynamic orderArgs = settings.arguments;
              final order = orderArgs is DeliveryOrder ? orderArgs : null;
              return MaterialPageRoute<void>(
                builder: (_) => OrderDetailsScreen(order: order),
              );
            case AppRoutes.navigation:
              return MaterialPageRoute<void>(
                builder: (_) => const NavigationScreen(),
              );
            case AppRoutes.deliveryList:
              return MaterialPageRoute<void>(
                builder: (_) => const DeliveryListScreen(),
              );
            case AppRoutes.deliveryTracking:
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute<void>(
                builder: (_) => DeliveryTrackingScreen(
                  deliveryName: args?['name'],
                  customerName: args?['customerName'],
                  storeName: args?['storeName'],
                  contactNumber: args?['contactNumber'],
                  dropAddress: args?['dropAddress'],
                  pickupLat: args?['pickupLat'],
                  pickupLng: args?['pickupLng'],
                  dropLat: args?['dropLat'],
                  dropLng: args?['dropLng'],
                ),
              );
            case AppRoutes.orderStatus:
              return MaterialPageRoute<void>(
                builder: (_) => const OrderStatusScreen(),
              );
            case AppRoutes.orderTracking:
              return MaterialPageRoute<void>(
                builder: (_) => const OrderTrackingScreen(),
              );
            case AppRoutes.dashboard:
              // Route guard: Force location selection if not selected
              if (!controller.bootstrapped) {
                return MaterialPageRoute<void>(
                  builder: (_) => const SplashScreen(),
                );
              }
              if (controller.isLoggedIn && !controller.hasSelectedLocation) {
                return MaterialPageRoute<void>(
                  builder: (_) => const CurrentLocationPickerScreen(),
                );
              }
              return MaterialPageRoute<void>(
                builder: (_) => const DashboardScreen(),
              );
            case AppRoutes.profile:
              return MaterialPageRoute<void>(
                builder: (_) => const ProfileScreen(),
              );
            case AppRoutes.ordersByLocation:
              return MaterialPageRoute<void>(
                builder: (_) => const OrdersByLocationScreen(),
              );
            case AppRoutes.settings:
              return MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              );
            case AppRoutes.externalDeliveryTripList:
              return MaterialPageRoute<void>(
                builder: (_) => const ExternalDeliveryTripListScreen(),
              );
            case AppRoutes.externalDeliveryTripDetails:
              final tripName = settings.arguments as String?;
              return MaterialPageRoute<void>(
                builder: (_) =>
                    ExternalDeliveryTripDetailsScreen(tripName: tripName ?? ''),
              );
            case AppRoutes.notifications:
              return MaterialPageRoute<void>(
                builder: (_) => const NotificationsScreen(),
              );
            case AppRoutes.myOrders:
              return MaterialPageRoute<void>(
                builder: (_) => const MyOrdersScreen(),
              );
            case AppRoutes.more:
              return MaterialPageRoute<void>(
                builder: (_) => const MoreScreen(),
              );
            case AppRoutes.security:
              return MaterialPageRoute<void>(
                builder: (_) => const SecurityScreen(),
              );
            case AppRoutes.pickupPool:
              return MaterialPageRoute<void>(
                builder: (_) => const PickupPoolScreen(),
              );
            case AppRoutes.pickupJobDetail:
              final jobName = settings.arguments as String? ?? '';
              return MaterialPageRoute<void>(
                builder: (_) => PickupJobDetailScreen(pickupJobName: jobName),
              );
            case AppRoutes.earnings:
              return MaterialPageRoute<void>(
                builder: (_) => const StatsScreen(),
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

class _AppLockObserver extends ConsumerStatefulWidget {
  const _AppLockObserver({required this.child});
  final Widget child;

  @override
  ConsumerState<_AppLockObserver> createState() => _AppLockObserverState();
}

class _AppLockObserverState extends ConsumerState<_AppLockObserver>
    with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (ref.read(appLockEnabledProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(appLockedProvider.notifier).lock();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ref.read(appLockEnabledProvider)) return;

    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _pausedAt != null) {
      final elapsed = DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      final index = ref.read(autoLockIndexProvider);
      final threshold = autoLockThreshold(index);
      // threshold == null means "Immediately" — always lock on resume
      if (threshold == null || elapsed >= threshold) {
        ref.read(appLockedProvider.notifier).lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (ref.watch(appLockedProvider)) const LockScreen(),
      ],
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

class _NoInternetOverlayWithRetryState extends State<NoInternetOverlayWithRetry>
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
            Icon(Icons.refresh_rounded, color: AppTheme.oceanBlue, size: 18),
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
