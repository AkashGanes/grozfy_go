import 'package:flutter/material.dart';
import '../models/app_models.dart';
import '../navigation/app_routes.dart';
import '../state/app_scope.dart';
import '../theme/app_theme.dart';
import 'app_shell.dart';

class OrdersFooter extends StatelessWidget {
  const OrdersFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _FooterItem(
                icon: Icons.local_shipping_rounded,
                label: 'My Orders',
                onTap: () => _showOrdersBottomSheet(context),
              ),
              _FooterItem(
                icon: Icons.more_horiz_rounded,
                label: 'More',
                onTap: () => _showMoreMenu(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOrdersBottomSheet(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const _OrdersFullScreen()));
  }

  void _showMoreMenu(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Quick Access'),
            backgroundColor: AppTheme.oceanBlue,
            foregroundColor: Colors.white,
          ),
          body: ListView(
            children: [
              _MoreMenuItem(
                icon: Icons.person_outline_rounded,
                label: 'My Profile',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.profile);
                },
              ),
              _MoreMenuItem(
                icon: Icons.receipt_long_rounded,
                label: 'Earnings History',
                onTap: () {
                  Navigator.pop(context);
                  showInfoSnack(context, 'Earnings module coming soon');
                },
              ),
              _MoreMenuItem(
                icon: Icons.file_copy_outlined,
                label: 'Documents',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.kycDocuments);
                },
              ),
              _MoreMenuItem(
                icon: Icons.two_wheeler_rounded,
                label: 'Vehicle',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.vehicleDetails);
                },
              ),
              _MoreMenuItem(
                icon: Icons.account_balance_outlined,
                label: 'Bank Details',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.bankSetup);
                },
              ),
              _MoreMenuItem(
                icon: Icons.location_on_outlined,
                label: 'Orders by Location',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.ordersByLocation);
                },
              ),
              _MoreMenuItem(
                icon: Icons.delivery_dining_rounded,
                label: 'External Trips',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(
                    context,
                  ).pushNamed(AppRoutes.externalDeliveryTripList);
                },
              ),
              _MoreMenuItem(
                icon: Icons.support_agent_rounded,
                label: 'Support',
                onTap: () {
                  Navigator.pop(context);
                  showInfoSnack(context, 'Support coming soon');
                },
              ),
              _MoreMenuItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushNamed(AppRoutes.settings);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterItem extends StatelessWidget {
  const _FooterItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.oceanBlue, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 11,
                color: AppTheme.oceanBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrdersFullScreen extends StatefulWidget {
  const _OrdersFullScreen();

  @override
  State<_OrdersFullScreen> createState() => _OrdersFullScreenState();
}

class _OrdersFullScreenState extends State<_OrdersFullScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final activeOrder = app.activeOrder;
    final currentOrders = app.currentOrders
        .where((o) => o.orderId != activeOrder?.orderId)
        .toList();
    final pastOrders = app.pastOrders;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        backgroundColor: AppTheme.oceanBlue,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Active'),
                  if (activeOrder != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '1',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Current'),
                  if (currentOrders.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${currentOrders.length}',
                        style: const TextStyle(
                          color: AppTheme.oceanBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Past'),
                  if (pastOrders.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${pastOrders.length}',
                        style: const TextStyle(
                          color: AppTheme.oceanBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OrdersList(
            orders: activeOrder != null ? [activeOrder] : [],
            emptyMessage: 'No active order',
            emptyIcon: Icons.local_shipping_outlined,
            isCurrentOrder: true,
          ),
          _OrdersList(
            orders: currentOrders,
            emptyMessage: 'No current orders',
            emptyIcon: Icons.local_shipping_outlined,
            isCurrentOrder: true,
          ),
          _OrdersList(
            orders: pastOrders,
            emptyMessage: 'No past orders',
            emptyIcon: Icons.history_outlined,
            isCurrentOrder: false,
          ),
        ],
      ),
    );
  }
}

class _MoreMenuItem extends StatelessWidget {
  const _MoreMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.oceanBlue),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}

class _OrdersBottomSheet extends StatefulWidget {
  const _OrdersBottomSheet();

  @override
  State<_OrdersBottomSheet> createState() => _OrdersBottomSheetState();
}

class _OrdersBottomSheetState extends State<_OrdersBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final currentOrders = app.currentOrders;
    final pastOrders = app.pastOrders;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabController,
                labelColor: AppTheme.oceanBlue,
                unselectedLabelColor: Colors.grey,
                indicatorColor: AppTheme.oceanBlue,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Current Orders'),
                        if (currentOrders.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.oceanBlue,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${currentOrders.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Past Orders'),
                        if (pastOrders.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${pastOrders.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _OrdersList(
                      orders: currentOrders,
                      emptyMessage: 'No current orders',
                      emptyIcon: Icons.local_shipping_outlined,
                      isCurrentOrder: true,
                    ),
                    _OrdersList(
                      orders: pastOrders,
                      emptyMessage: 'No past orders',
                      emptyIcon: Icons.history_outlined,
                      isCurrentOrder: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({
    required this.orders,
    required this.emptyMessage,
    required this.emptyIcon,
    required this.isCurrentOrder,
  });

  final List<DeliveryOrder> orders;
  final String emptyMessage;
  final IconData emptyIcon;
  final bool isCurrentOrder;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(emptyIcon, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              emptyMessage,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return _OrderCard(order: order, isCurrentOrder: isCurrentOrder);
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.isCurrentOrder});

  final DeliveryOrder order;
  final bool isCurrentOrder;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushNamed(AppRoutes.orderDetails);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      order.orderId,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  _StatusBadge(status: order.orderStatus),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.store, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.storeName,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.person, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.customerName,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 14,
                    color: isCurrentOrder ? AppTheme.oceanBlue : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.drop.isNotEmpty
                          ? order.drop
                          : order.deliveryAddress,
                      style: TextStyle(
                        fontSize: 12,
                        color: isCurrentOrder
                            ? AppTheme.oceanBlue
                            : Colors.grey,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (isCurrentOrder) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).pushNamed(AppRoutes.orderDetails);
                      },
                      icon: const Icon(Icons.visibility, size: 16),
                      label: const Text('View'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).pushNamed(AppRoutes.navigation);
                      },
                      icon: const Icon(Icons.navigation, size: 16),
                      label: const Text('Navigate'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.mint,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final OrderStatus status;

  Color get _backgroundColor {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange.shade100;
      case OrderStatus.accepted:
      case OrderStatus.reachedPickup:
        return Colors.blue.shade100;
      case OrderStatus.pickedUp:
        return Colors.purple.shade100;
      case OrderStatus.outForDelivery:
        return Colors.indigo.shade100;
      case OrderStatus.delivered:
        return Colors.green.shade100;
      case OrderStatus.cancelled:
      case OrderStatus.rejected:
        return Colors.red.shade100;
    }
  }

  Color get _textColor {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange.shade800;
      case OrderStatus.accepted:
      case OrderStatus.reachedPickup:
        return Colors.blue.shade800;
      case OrderStatus.pickedUp:
        return Colors.purple.shade800;
      case OrderStatus.outForDelivery:
        return Colors.indigo.shade800;
      case OrderStatus.delivered:
        return Colors.green.shade800;
      case OrderStatus.cancelled:
      case OrderStatus.rejected:
        return Colors.red.shade800;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: _textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
