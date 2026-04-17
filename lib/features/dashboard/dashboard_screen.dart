import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import '../../features/notifications/providers/notification_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = AppScope.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(context, app),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 140),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!app.isKycComplete) ...[
                          KYCWarningBanner(
                            title: 'Action Required',
                            message:
                                'Your document verification is pending. Please complete your KYC to avoid service interruptions.',
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed(AppRoutes.kycDocuments),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _buildAvailabilityCard(context, app),
                        const SizedBox(height: 16),
                        if (app.activeOrder != null) ...[
                          _buildActiveOrderCard(context, app),
                          const SizedBox(height: 16),
                        ],
                        _buildEarningsSection(context, app),
                        const SizedBox(height: 16),
                        _buildPerformanceSection(context, app),
                        const SizedBox(height: 24),
                        _buildPrimaryServicesSection(context, app),
                        const SizedBox(height: 24),
                        _buildManagementSection(context, app),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildSimulateButton(context, app),
          _buildBottomNav(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, dynamic app) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Navigator',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    fontFamily: 'Manrope',
                  ),
                ),
                Text(
                  app.profile?.fullName ?? 'Delivery Partner',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.outline,
                  ),
                ),
              ],
            ),
          ),
          Consumer(
            builder: (context, ref, _) {
              final totalCount = ref.watch(totalUnreadCountProvider);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () async {
                    await Navigator.of(
                      context,
                    ).pushNamed(AppRoutes.notifications);
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        Icons.notifications_outlined,
                        color: AppColors.primary,
                        size: 22,
                      ),
                      if (totalCount > 0)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              totalCount > 9 ? '9+' : totalCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          OnlineStatusIndicator(isOnline: app.isOnline),
        ],
      ),
    );
  }

  Widget _buildAvailabilityCard(BuildContext context, dynamic app) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A181D1A),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Availability',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        fontFamily: 'Manrope',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      app.isOnline
                          ? 'Accepting new orders'
                          : 'Not accepting orders',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 56,
                height: 32,
                decoration: BoxDecoration(
                  color: app.isOnline
                      ? AppColors.primary
                      : AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      final String? error = app.setOnline(!app.isOnline);
                      if (error != null) {
                        showInfoSnack(context, error);
                      }
                    },
                    child: Align(
                      alignment: app.isOnline
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x29000000),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on, color: AppColors.secondary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CURRENT LOCATION',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.outline,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        app.currentLocationLabel ?? 'Location not selected',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed(AppRoutes.currentLocation);
                  },
                  child: Text(
                    app.hasSelectedLocation ? 'Change' : 'Select',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (app.notices.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'SYSTEM NOTICES',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.outline,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: app.notices
                    .take(4)
                    .toList()
                    .asMap()
                    .entries
                    .map<Widget>((entry) {
                      final index = entry.key;
                      final notice = entry.value as AppNotice;
                      final isLast =
                          index == (app.notices.length - 1).clamp(0, 3);

                      Color indicatorColor = AppColors.primary;
                      final titleLower = notice.title.toLowerCase();
                      if (titleLower.contains('rain') ||
                          titleLower.contains('forecast') ||
                          titleLower.contains('payout') ||
                          titleLower.contains('successful')) {
                        indicatorColor = AppColors.outlineVariant;
                      } else if (titleLower.contains('policy') ||
                          titleLower.contains('alert') ||
                          titleLower.contains('update')) {
                        indicatorColor = AppColors.error;
                      }

                      return NotificationListItem(
                        title: notice.title,
                        message: notice.message,
                        time: _timeAgo(notice.time),
                        indicatorColor: indicatorColor,
                        isLast: isLast,
                      );
                    })
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveOrderCard(BuildContext context, dynamic app) {
    final order = app.activeOrder as DeliveryOrder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Active Delivery',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: 'Manrope',
              ),
            ),
            const StatusBadge(
              label: 'IN PROGRESS',
              backgroundColor: Color(0x4D959EFD),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A181D1A),
                blurRadius: 24,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.restaurant,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order #${order.orderId}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.outline,
                            ),
                          ),
                          Text(
                            order.storeName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    'Rs. ${order.estimatedEarnings.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      fontFamily: 'Manrope',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              OrderTrackingVisual(
                pickupLabel: 'Pickup',
                pickupAddress: order.pickup.isNotEmpty
                    ? order.pickup
                    : order.storeAddress,
                dropoffLabel: 'Dropoff',
                dropoffAddress: order.drop.isNotEmpty
                    ? order.drop
                    : order.deliveryAddress,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      onPressed: () {
                        Navigator.of(context).pushNamed(AppRoutes.orderDetails);
                      },
                      label: 'Details',
                      icon: Icons.info_outline,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      onPressed: () {
                        Navigator.of(context).pushNamed(AppRoutes.navigation);
                      },
                      label: 'Navigate',
                      icon: Icons.navigation,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEarningsSection(BuildContext context, dynamic app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Earnings Summary',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            fontFamily: 'Manrope',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Today',
                value: 'Rs. ${app.earnings.today.toStringAsFixed(0)}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: 'This Week',
                value: 'Rs. ${app.earnings.week.toStringAsFixed(0)}',
                valueColor: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Total',
                value: 'Rs. ${app.earnings.total.toStringAsFixed(0)}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: 'Pending Payout',
                value: 'Rs. ${app.earnings.pendingPayout.toStringAsFixed(0)}',
                valueColor: AppColors.tertiary,
                backgroundColor: AppColors.tertiaryContainer.withValues(
                  alpha: 0.1,
                ),
                borderColor: AppColors.tertiary.withValues(alpha: 0.1),
                isHighlighted: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPerformanceSection(BuildContext context, dynamic app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Performance Metrics',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            fontFamily: 'Manrope',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Rating',
                value: '${app.performance.rating.toStringAsFixed(1)} star',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: 'Acceptance',
                value: '${app.performance.acceptanceRate.toStringAsFixed(1)}%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Completion',
                value: '${app.performance.completionRate.toStringAsFixed(1)}%',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: 'Total Deliveries',
                value: '${app.performance.totalDeliveries}',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPrimaryServicesSection(BuildContext context, dynamic app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Primary Services',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.outline,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        PrimaryServiceCard(
          title: 'Delivery Orders',
          subtitle: '24 completed this week',
          icon: Icons.local_shipping,
          iconColor: AppColors.primary,
          onTap: () {
            Navigator.of(context).pushNamed(AppRoutes.deliveryList);
          },
        ),
        const SizedBox(height: 12),
        PrimaryServiceCard(
          title: 'Multi-Order Pickup',
          subtitle: 'Pick up multiple orders in one trip',
          icon: Icons.playlist_add_check,
          iconColor: AppColors.tertiary,
          onTap: () {
            Navigator.of(context).pushNamed(AppRoutes.ordersByLocation);
          },
        ),
        const SizedBox(height: 12),
        PrimaryServiceCard(
          title: 'External Trips',
          subtitle: 'View available long-haul routes',
          icon: Icons.explore,
          iconColor: AppColors.secondary,
          onTap: () {
            Navigator.of(context).pushNamed(AppRoutes.externalDeliveryTripList);
          },
        ),
      ],
    );
  }

  Widget _buildManagementSection(BuildContext context, dynamic app) {
    return const SizedBox.shrink();
  }

  Widget _buildSimulateButton(BuildContext context, dynamic app) {
    return Positioned(
      bottom: 100,
      left: 24,
      right: 24,
      child: GradientButton(
        onPressed: () {
          app.generateIncomingOrder();
          Navigator.of(context).pushNamed(AppRoutes.orderRequest);
        },
        label: 'SIMULATE INCOMING ORDER',
        icon: Icons.flash_on,
        fromColor: AppColors.primary,
        toColor: AppColors.primaryContainer,
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest.withValues(alpha: 0.9),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A181D1A),
              blurRadius: 24,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(
              icon: Icons.home,
              label: 'Home',
              isSelected: true,
              onTap: () {},
            ),
            _buildNavItem(
              icon: Icons.local_shipping_outlined,
              label: 'Orders',
              isSelected: false,
              onTap: () {
                Navigator.of(context).pushNamed(AppRoutes.orderListing);
              },
            ),
            _buildNavItem(
              icon: Icons.payments_outlined,
              label: 'Earnings',
              isSelected: false,
              onTap: () {
                Navigator.of(context).pushNamed(AppRoutes.earnings);
              },
            ),
            _buildNavItem(
              icon: Icons.person_outline,
              label: 'Profile',
              isSelected: false,
              onTap: () {
                Navigator.of(context).pushNamed(AppRoutes.profile);
              },
            ),
            _buildNavItem(
              icon: Icons.more_horiz,
              label: 'More',
              isSelected: false,
              onTap: () {
                _showMoreMenu(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected
                  ? AppColors.onPrimary
                  : AppColors.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? AppColors.onPrimary
                    : AppColors.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime time) {
    final Duration diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) {
      return 'just now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }
    return '${diff.inDays}d ago';
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Management',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.outline,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 16),
            _buildMoreMenuItem(
              icon: Icons.person_outline,
              title: 'My Profile',
              onTap: () {
                Navigator.of(context).pushNamed(AppRoutes.profile);
              },
            ),
            _buildMoreMenuItem(
              icon: Icons.receipt_long_outlined,
              title: 'Earnings History',
              onTap: () {},
            ),
            _buildMoreMenuItem(
              icon: Icons.description_outlined,
              title: 'Documents',
              onTap: () {
                Navigator.of(context).pushNamed(AppRoutes.kycDocuments);
              },
            ),
            _buildMoreMenuItem(
              icon: Icons.directions_car_outlined,
              title: 'Vehicle Info',
              trailing: Text(
                'Toyota Prius',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.outline,
                ),
              ),
              onTap: () {
                Navigator.of(context).pushNamed(AppRoutes.vehicleDetails);
              },
            ),
            _buildMoreMenuItem(
              icon: Icons.account_balance_outlined,
              title: 'Bank Details',
              onTap: () {
                Navigator.of(context).pushNamed(AppRoutes.bankSetup);
              },
            ),
            _buildMoreMenuItem(
              icon: Icons.verified_user_outlined,
              iconColor: AppColors.tertiary,
              title: 'KYC Documents',
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.tertiaryFixed,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'PENDING',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onTertiaryFixedVariant,
                  ),
                ),
              ),
              onTap: () {
                Navigator.of(context).pushNamed(AppRoutes.kycDocuments);
              },
            ),
            _buildMoreMenuItem(
              icon: Icons.map_outlined,
              title: 'Orders by Location',
              onTap: () {
                Navigator.of(context).pushNamed(AppRoutes.ordersByLocation);
              },
            ),
            _buildMoreMenuItem(
              icon: Icons.headset_mic_outlined,
              title: 'Support',
              onTap: () {},
            ),
            _buildMoreMenuItem(
              icon: Icons.settings_outlined,
              title: 'Settings',
              showDivider: false,
              onTap: () {
                Navigator.of(context).pushNamed(AppRoutes.settings);
              },
            ),
            const SizedBox(height: 34),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Widget? trailing,
    Color? iconColor,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: iconColor ?? AppColors.outline, size: 22),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                trailing ??
                    Icon(
                      Icons.chevron_right,
                      color: AppColors.outline,
                      size: 20,
                    ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: AppColors.outline.withValues(alpha: 0.1)),
      ],
    );
  }
}
