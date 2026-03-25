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
import 'features/orders/order_listing_screen.dart';
import 'features/orders/order_request_screen.dart';
import 'features/orders/order_status_screen.dart';
import 'features/orders/order_tracking_screen.dart';
import 'features/permissions/location_permission_screen.dart';
import 'features/splash/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: DeliveryPartnerApp()));
}

class DeliveryPartnerApp extends ConsumerWidget {
  const DeliveryPartnerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    return AppScope(
      controller: controller,
      child: MaterialApp(
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
            case AppRoutes.orderListing:
              return MaterialPageRoute<void>(
                builder: (_) => const OrderListingScreen(),
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
            case AppRoutes.orderTracking:
              return MaterialPageRoute<void>(
                builder: (_) => const OrderTrackingScreen(),
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
