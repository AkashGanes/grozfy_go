import 'package:flutter/material.dart';

/// Zero-duration route used for bottom-nav tab switches so there is no slide
/// animation in any direction — all three tabs feel like a single surface.
class NoAnimRoute<T> extends MaterialPageRoute<T> {
  NoAnimRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

class AppRoutes {
  static const splash = '/';
  static const language = '/language';
  static const login = '/login';
  static const otp = '/otp';
  static const register = '/register';
  static const kycDocuments = '/kyc-documents';
  static const vehicleDetails = '/vehicle-details';
  static const vehicleSubmittedDetails = '/vehicle-submitted-details';
  static const bankSetup = '/bank-setup';
  static const bankSubmittedDetails = '/bank-submitted-details';
  static const permission = '/permission';
  static const tracking = '/tracking';
  static const currentLocation = '/current-location';
  static const orderListing = '/order-listing';
  static const orderRequest = '/order-request';
  static const orderDetails = '/order-details';
  static const navigation = '/navigation';
  static const deliveryList = '/delivery-list';
  static const deliveryTracking = '/delivery-tracking';
  static const orderStatus = '/order-status';
  static const orderTracking = '/order-tracking';
  static const dashboard = '/dashboard';
  static const profile = '/profile';
  static const externalDeliveryTripList = '/external-delivery-trip-list';
  static const externalDeliveryTripDetails = '/external-delivery-trip-details';
  static const settings = '/settings';
  static const notifications = '/notifications';
  static const myOrders = '/my-orders';
  static const more = '/more';
  static const earnings = '/earnings';
  static const security = '/security';
  static const pickupPool = '/pickup-pool';
  static const pickupJobDetail = '/pickup-job-detail';
  static const support = '/support';
  static const codSettlement = '/cod-settlement';
  static const orderBreakdown = '/order-breakdown';

  // Privacy & Legal module. `legal` is the hub in reference mode;
  // `legalConsent` is the same screen as the onboarding gate and pops `true`
  // once the driver accepts.
  static const legal = '/legal';
  static const legalConsent = '/legal/consent';
  static const legalPrivacy = '/legal/privacy-policy';
  static const legalDataDetail = '/legal/privacy-policy/data';
  static const legalTerms = '/legal/terms';
  static const legalPermissions = '/legal/permissions';
  static const legalContact = '/legal/contact';
  static const legalDeleteAccount = '/legal/delete-account';
}
