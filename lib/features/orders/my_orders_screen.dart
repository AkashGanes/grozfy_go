import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_bottom_nav.dart';
import '../orders_by_location/model/external_delivery.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';

class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> {
  int _selectedTab = 0;

  final ExternalDeliveryRepository _repo = ExternalDeliveryRepository();

  List<DeliveryOrder> _pastOrders = [];
  bool _isPastLoading = true;
  String? _pastError;
  Future<void>? _pastFuture;

  @override
  void initState() {
    super.initState();
    _loadPastOrders();
  }

  DeliveryOrder _summaryToOrder(ExternalDelivery s) {
    final status = ref.read(appControllerProvider).mapStatus(s.status);
    final address = s.deliveryAddress != null
        ? Formatters.stripHtml(s.deliveryAddress!, preserveLineBreaks: false)
        : '';
    return DeliveryOrder(
      id: s.name,
      orderId: s.name,
      customerName: s.customerName,
      customerPhone: '',
      deliveryAddress: address,
      storeId: s.storeUrl.isNotEmpty ? s.storeUrl : s.storeName,
      storeName: s.storeName,
      storeContact: '',
      storeAddress: '',
      orderItems: const [],
      orderStatus: status,
      latitude: 0,
      longitude: 0,
      pickup: '',
      drop: address,
      paymentMode: '',
      distanceKm: 0,
      estimatedEarnings: 0,
      assignmentStatus: status == OrderStatus.pending
          ? OrderAssignmentStatus.unassigned
          : OrderAssignmentStatus.assigned,
    );
  }

  Future<void> _loadPastOrders() async {
    if (_pastFuture != null) return;
    _pastFuture = _doLoadPast();
    await _pastFuture;
    _pastFuture = null;
  }

  Future<void> _doLoadPast() async {
    setState(() {
      _isPastLoading = true;
      _pastError = null;
    });
    try {
      final summaries = await _repo.fetchPastOrdersForDriver();
      final orders = summaries.map(_summaryToOrder).toList();
      if (mounted) {
        setState(() {
          _pastOrders = orders;
          _isPastLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pastError = e.toString();
          _isPastLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final activeOrder = ref.watch(appControllerProvider).activeOrder;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).scaffoldBackgroundColor,
                  ]
                : const [
                    Color(0xFFF1F7FF),
                    Color(0xFFE8F5F0),
                    Color(0xFFFFF5E6),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            _buildBackdrop(),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildHeader(),
                  _buildTabBar(activeOrder),
                  Expanded(
                    child: _selectedTab == 0
                        ? _buildActiveList(activeOrder)
                        : _buildPastList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 1,
        onTap: (index) {
          if (index == 0) {
            Navigator.of(context).pushNamed(AppRoutes.dashboard);
          } else if (index == 2) {
            Navigator.of(context).pushNamed(AppRoutes.more);
          }
        },
      ),
    );
  }

  Widget _buildBackdrop() {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: -40,
            top: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppTheme.oceanBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: -20,
            top: 80,
            child: Transform.rotate(
              angle: 0.8,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.mango.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          Positioned(
            left: 30,
            bottom: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: AppTheme.mint.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          if (Navigator.canPop(context))
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 22),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'My Orders',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Track your deliveries',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(DeliveryOrder? activeOrder) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedTab = 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _selectedTab == 0
                        ? AppTheme.oceanBlue
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      activeOrder != null ? 'Active (1)' : 'Active (0)',
                      style: TextStyle(
                        color: _selectedTab == 0
                            ? Colors.white
                            : scheme.onSurface.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedTab = 1),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _selectedTab == 1
                        ? AppTheme.oceanBlue
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      _isPastLoading
                        ? 'Past'
                        : 'Past (${_pastOrders.length})',
                      style: TextStyle(
                        color: _selectedTab == 1
                            ? Colors.white
                            : scheme.onSurface.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveList(DeliveryOrder? activeOrder) {
    if (activeOrder == null) {
      return const Center(child: Text('No active orders.'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        _OrderCard(
          order: activeOrder,
          onTap: () => Navigator.of(context).pushNamed(
            AppRoutes.orderDetails,
            arguments: activeOrder,
          ),
        ),
      ],
    );
  }

  Widget _buildPastList() {
    if (_isPastLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pastError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                'Failed to load orders',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _pastError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadPastOrders,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_pastOrders.isEmpty) {
      return const Center(child: Text('No past orders found.'));
    }
    return RefreshIndicator(
      onRefresh: _loadPastOrders,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: _pastOrders.length,
        itemBuilder: (context, index) => _OrderCard(
          order: _pastOrders[index],
          onTap: () => Navigator.of(context).pushNamed(
            AppRoutes.orderDetails,
            arguments: _pastOrders[index],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              icon: Icons.home_rounded,
              label: 'Home',
              isSelected: false,
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.dashboard),
            ),
            _NavItem(
              icon: Icons.local_shipping_rounded,
              label: 'My Orders',
              isSelected: true,
              onTap: () {},
            ),
            _NavItem(
              icon: Icons.more_horiz_rounded,
              label: 'More',
              isSelected: false,
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.more),
            ),
          ],
        ),
      ),
    );
  }


}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? AppTheme.oceanBlue
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? AppTheme.oceanBlue
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, this.onTap});
  final DeliveryOrder order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(order.orderStatus);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? scheme.outline.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.7),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    order.orderStatus.label,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  order.orderId,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildInfo(Icons.store_rounded, order.storeName),
            _buildInfo(Icons.more_horiz_rounded, order.customerName),
            _buildInfo(
              Icons.location_on_rounded,
              order.drop.isNotEmpty ? order.drop : order.deliveryAddress,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.mint.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Rs. ${order.estimatedEarnings.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: AppTheme.mint,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${order.distanceKm.toStringAsFixed(1)} km',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(IconData icon, String text) {
    return Builder(
      builder: (context) {
        final ColorScheme scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
            ],
          ),
        );
      },
    );
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.accepted:
        return AppTheme.oceanBlue;
      case OrderStatus.rejected:
        return Colors.red;
      case OrderStatus.reachedPickup:
        return Colors.purple;
      case OrderStatus.pickedUp:
        return Colors.blue;
      case OrderStatus.outForDelivery:
        return AppTheme.mango;
      case OrderStatus.delivered:
        return AppTheme.mint;
      case OrderStatus.cancelled:
        return Colors.red;
    }
  }
}

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).scaffoldBackgroundColor,
                  ]
                : const [
                    Color(0xFFF1F7FF),
                    Color(0xFFE8F5F0),
                    Color(0xFFFFF5E6),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            _buildBackdrop(),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildMenu()),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 2,
        onTap: (index) {
          if (index == 0) {
            Navigator.of(context).pushNamed(AppRoutes.dashboard);
          } else if (index == 1) {
            Navigator.of(context).pushNamed(AppRoutes.myOrders);
          }
        },
      ),
    );
  }

  Widget _buildBackdrop() {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: -40,
            top: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppTheme.oceanBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: -20,
            top: 80,
            child: Transform.rotate(
              angle: 0.8,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.mango.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          Positioned(
            left: 30,
            bottom: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: AppTheme.mint.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'More',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Quick Access',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenu() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _menuItem(Icons.person_rounded, 'My Profile', AppRoutes.profile),
        _menuItem(
          Icons.list_alt_rounded,
          'Available Orders',
          AppRoutes.orderListing,
        ),
        // _menuItem(
        //   Icons.location_on_rounded,
        //   'Orders by Location',
        //   AppRoutes.ordersByLocation,
        // ),
        _menuItem(
          Icons.route_rounded,
          'External Trips',
          AppRoutes.externalDeliveryTripList,
        ),
        _menuItem(Icons.settings_rounded, 'Settings', AppRoutes.settings),
        _menuItem(Icons.security_rounded, 'Security', AppRoutes.security),
        _menuItem(
          Icons.monetization_on_rounded,
          'Earnings History',
          AppRoutes.settings,
        ),
        _menuItem(
          Icons.car_rental_rounded,
          'Vehicle',
          AppRoutes.vehicleDetails,
        ),
        _menuItem(
          Icons.account_balance_rounded,
          'Bank Details',
          AppRoutes.bankSetup,
        ),
        _menuItem(
          Icons.description_rounded,
          'Documents',
          AppRoutes.kycDocuments,
        ),
        _menuItem(Icons.help_rounded, 'Support', AppRoutes.settings),
      ],
    );
  }

  Widget _menuItem(IconData icon, String label, String route) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.oceanBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.oceanBlue, size: 20),
        ),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: scheme.onSurface.withValues(alpha: 0.4),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: scheme.surface.withValues(alpha: 0.8),
        onTap: () => Navigator.of(context).pushNamed(route),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              icon: Icons.home_rounded,
              label: 'Home',
              isSelected: false,
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.dashboard),
            ),
            _NavItem(
              icon: Icons.local_shipping_rounded,
              label: 'My Orders',
              isSelected: false,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            _NavItem(
              icon: Icons.more_horiz_rounded,
              label: 'More',
              isSelected: true,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}
