import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_theme.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF1F7FF), Color(0xFFE8F5F0), Color(0xFFFFF5E6)],
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
                  _buildTabBar(),
                  Expanded(
                    child: _selectedTab == 0
                        ? _buildActiveList()
                        : _buildPastList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
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
          if (Navigator.canPop(context))
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 22),
            ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'My Orders',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Track your deliveries',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
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
                      'Active (1)',
                      style: TextStyle(
                        color: _selectedTab == 0
                            ? Colors.white
                            : Colors.black54,
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
                      'Past (3)',
                      style: TextStyle(
                        color: _selectedTab == 1
                            ? Colors.white
                            : Colors.black54,
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

  Widget _buildActiveList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _getActiveOrders().length,
      itemBuilder: (context, index) => _OrderCard(
        order: _getActiveOrders()[index],
        onTap: () => Navigator.of(context).pushNamed(
          AppRoutes.orderDetails,
          arguments: _getActiveOrders()[index],
        ),
      ),
    );
  }

  Widget _buildPastList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _getPastOrders().length,
      itemBuilder: (context, index) => _OrderCard(
        order: _getPastOrders()[index],
        onTap: () => Navigator.of(
          context,
        ).pushNamed(AppRoutes.orderDetails, arguments: _getPastOrders()[index]),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
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

  List<DeliveryOrder> _getActiveOrders() => [
    DeliveryOrder(
      orderId: '#OD3001',
      customerName: 'Sneha Gupta',
      customerPhone: '9876512345',
      deliveryAddress: 'Saket, New Delhi - 110017',
      storeId: 'STORE200',
      storeName: 'Pizza Palace',
      storeContact: '9876598765',
      storeAddress: 'Dwarka, New Delhi',
      orderItems: const [
        OrderItem(name: 'Pepperoni Pizza', quantity: 2, price: 450),
      ],
      orderStatus: OrderStatus.accepted,
      latitude: 28.5692,
      longitude: 77.1538,
      pickup: 'Dwarka',
      drop: 'Saket',
      paymentMode: 'Online',
      distanceKm: 5.2,
      estimatedEarnings: 145,
      assignmentStatus: OrderAssignmentStatus.assigned,
    ),
  ];

  List<DeliveryOrder> _getPastOrders() => [
    DeliveryOrder(
      orderId: '#OD2001',
      customerName: 'Riya Sharma',
      customerPhone: '9876510001',
      deliveryAddress: 'Connaught Place, New Delhi',
      storeId: 'STORE100',
      storeName: 'Fresh Bites Kitchen',
      storeContact: '9876543210',
      storeAddress: 'Karol Bagh',
      orderItems: const [
        OrderItem(name: 'Veg Biryani', quantity: 1, price: 180),
      ],
      orderStatus: OrderStatus.delivered,
      latitude: 28.6139,
      longitude: 77.2090,
      pickup: 'Karol Bagh',
      drop: 'Connaught Place',
      paymentMode: 'COD',
      distanceKm: 4.0,
      estimatedEarnings: 80,
      assignmentStatus: OrderAssignmentStatus.assigned,
    ),
    DeliveryOrder(
      orderId: '#OD2002',
      customerName: 'Amit Kumar',
      customerPhone: '9876510002',
      deliveryAddress: 'Karol Bagh, New Delhi',
      storeId: 'STORE101',
      storeName: 'Tasty Treats',
      storeContact: '9876543211',
      storeAddress: 'Lajpat Nagar',
      orderItems: const [
        OrderItem(name: 'Chicken Curry', quantity: 1, price: 250),
      ],
      orderStatus: OrderStatus.delivered,
      latitude: 28.6339,
      longitude: 77.2290,
      pickup: 'Lajpat Nagar',
      drop: 'Karol Bagh',
      paymentMode: 'Online',
      distanceKm: 3.5,
      estimatedEarnings: 70,
      assignmentStatus: OrderAssignmentStatus.assigned,
    ),
    DeliveryOrder(
      orderId: '#OD2003',
      customerName: 'Priya Singh',
      customerPhone: '9876510003',
      deliveryAddress: 'Lajpat Nagar, New Delhi',
      storeId: 'STORE102',
      storeName: 'Burger Barn',
      storeContact: '9876543212',
      storeAddress: 'Saket',
      orderItems: const [
        OrderItem(name: 'Classic Burger', quantity: 2, price: 150),
      ],
      orderStatus: OrderStatus.cancelled,
      latitude: 28.6539,
      longitude: 77.2490,
      pickup: 'Saket',
      drop: 'Lajpat Nagar',
      paymentMode: 'COD',
      distanceKm: 6.0,
      estimatedEarnings: 60,
      assignmentStatus: OrderAssignmentStatus.assigned,
    ),
  ];
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
              color: isSelected ? AppTheme.oceanBlue : Colors.black54,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppTheme.oceanBlue : Colors.black54,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140A1D3A),
              blurRadius: 12,
              offset: Offset(0, 6),
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
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.black54),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
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
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF1F7FF), Color(0xFFE8F5F0), Color(0xFFFFF5E6)],
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
      bottomNavigationBar: _buildBottomNav(),
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'More',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Quick Access',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
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
        _menuItem(
          Icons.location_on_rounded,
          'Orders by Location',
          AppRoutes.ordersByLocation,
        ),
        _menuItem(
          Icons.route_rounded,
          'External Trips',
          AppRoutes.externalDeliveryTripList,
        ),
        _menuItem(Icons.settings_rounded, 'Settings', AppRoutes.settings),
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
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Colors.black38,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: Colors.white.withValues(alpha: 0.8),
        onTap: () => Navigator.of(context).pushNamed(route),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
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
