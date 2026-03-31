import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/services/fcm_initializer.dart';
import 'core/navigation/app_routes.dart';
import 'core/state/providers.dart';
import 'core/state/app_scope.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/notifications/ui/screens/notifications_screen.dart';
import 'features/kyc/bank_setup_screen.dart';
import 'features/kyc/bank_submitted_details_screen.dart';
import 'features/kyc/kyc_documents_screen.dart';
import 'features/kyc/vehicle_details_screen.dart';
import 'features/kyc/vehicle_submitted_details_screen.dart';
import 'features/language/language_selection_screen.dart';
import 'features/location/current_location_picker_screen.dart';
import 'features/location/location_tracking_screen.dart';
import 'features/orders/navigation_screen.dart';
import 'features/orders_by_location/ui/external_delivery_trip_details_screen.dart';
import 'features/orders_by_location/ui/external_delivery_trip_list_screen.dart';
import 'features/orders_by_location/ui/orders_by_location_screen.dart';
import 'features/orders/order_details_screen.dart';
import 'features/orders/order_request_screen.dart';
import 'features/orders/order_status_screen.dart';
import 'features/permissions/location_permission_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/splash/splash_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();

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

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const DeliveryPartnerApp(),
    ),
  );
}

class DeliveryPartnerApp extends ConsumerWidget {
  const DeliveryPartnerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    return AppScope(
      controller: controller,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'FlowFleet Partner',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        initialRoute: AppRoutes.splash,
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
