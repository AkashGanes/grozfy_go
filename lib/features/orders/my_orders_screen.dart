import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../orders_by_location/model/external_delivery.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';

class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> {
  int _selectedTab = 0;
  bool _isNavigating = false;

  final ExternalDeliveryRepository _repo = ExternalDeliveryRepository();

  List<DeliveryOrder> _activeOrders = [];
  bool _isActiveLoading = true;
  String? _activeError;
  Future<void>? _activeFuture;

  List<DeliveryOrder> _pastOrders = [];
  bool _isPastLoading = true;
  bool _isLoadingMorePast = false;
  bool _hasMorePast = false;
  int _pastLimitStart = 0;
  static const int _pastPageSize = 20;
  String? _pastError;
  Future<void>? _pastFuture;
  bool _pastLoadRequested = false;

  @override
  void initState() {
    super.initState();
    _loadActiveOrders();
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
      createdAt: s.creation.isNotEmpty ? DateTime.tryParse(s.creation) : null,
    );
  }

  Future<void> _loadPastOrders() async {
    if (_pastFuture != null) return;
    _pastLoadRequested = true;
    _pastFuture = _doLoadPast();
    await _pastFuture;
    _pastFuture = null;
  }

  Future<void> _loadActiveOrders() async {
    if (_activeFuture != null) return;
    _activeFuture = _doLoadActive();
    await _activeFuture;
    _activeFuture = null;
  }

  Future<void> _doLoadActive() async {
    setState(() {
      _isActiveLoading = true;
      _activeError = null;
    });
    try {
      final summaries = await _repo.fetchActiveOrdersForDriverDirect();
      final orders = summaries.map(_summaryToOrder).toList();
      if (mounted) {
        setState(() {
          _activeOrders = orders;
          _isActiveLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _activeError = e.toString();
          _isActiveLoading = false;
        });
      }
    }
  }

  Future<void> _doLoadPast() async {
    setState(() {
      _isPastLoading = true;
      _pastError = null;
      _pastLimitStart = 0;
    });
    try {
      final summaries = await _repo.fetchPastOrdersForDriver(
        limitStart: 0,
        limitPageLength: _pastPageSize,
      );
      final orders = summaries.map(_summaryToOrder).toList();
      if (mounted) {
        setState(() {
          _pastOrders = orders;
          _isPastLoading = false;
          _hasMorePast = summaries.length >= _pastPageSize;
          _pastLimitStart = summaries.length;
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

  void _handleTabTap(int index) {
    if (_isNavigating || index == 1) return;
    setState(() => _isNavigating = true);
    if (index == 0) {
      Navigator.of(context).maybePop().whenComplete(
        () {
          if (mounted) setState(() => _isNavigating = false);
        },
      );
    } else if (index == 2) {
      Navigator.of(context)
          .pushReplacement(
            NoAnimRoute(builder: (_) => const MoreScreen()),
          )
          .whenComplete(
            () {
              if (mounted) setState(() => _isNavigating = false);
            },
          );
    } else {
      setState(() => _isNavigating = false);
    }
  }

  Future<void> _loadMorePast() async {
    if (_isLoadingMorePast || !_hasMorePast) return;
    setState(() => _isLoadingMorePast = true);
    try {
      final summaries = await _repo.fetchPastOrdersForDriver(
        limitStart: _pastLimitStart,
        limitPageLength: _pastPageSize,
      );
      final orders = summaries.map(_summaryToOrder).toList();
      if (mounted) {
        setState(() {
          _pastOrders = [..._pastOrders, ...orders];
          _isLoadingMorePast = false;
          _hasMorePast = summaries.length >= _pastPageSize;
          _pastLimitStart += summaries.length;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMorePast = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appActiveOrder = ref.watch(appControllerProvider).activeOrder;
    final List<DeliveryOrder> activeOrders = _activeOrders.isNotEmpty
        ? _activeOrders
        : (appActiveOrder != null ? [appActiveOrder] : const []);
    return AppShell(
      title: 'My Orders',
      subtitle: 'Track your deliveries',
      padding: EdgeInsets.zero,
      scrollable: false,
      showBottomNav: true,
      bottomNavIndex: 1,
      onBottomNavTap: _handleTabTap,
      child: Column(
        children: [
          _buildTabBar(activeOrders),
          Expanded(
            child: _selectedTab == 0
                ? _buildActiveList(activeOrders)
                : _buildPastList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(List<DeliveryOrder> activeOrders) {
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
                      'Active (${activeOrders.length})',
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
                onTap: () {
                  setState(() => _selectedTab = 1);
                  if (!_pastLoadRequested && _pastFuture == null) {
                    _loadPastOrders();
                  }
                },
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

  Widget _buildActiveList(List<DeliveryOrder> activeOrders) {
    if (_activeError != null && activeOrders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              const Text(
                'Failed to load active orders',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _activeError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadActiveOrders,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (activeOrders.isEmpty && _isActiveLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (activeOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_shipping_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'No active orders',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadActiveOrders,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: activeOrders.length,
        itemBuilder: (context, index) {
          final order = activeOrders[index];
          return _OrderCard(
            order: order,
            onTap: () => Navigator.of(context).pushNamed(
              AppRoutes.orderDetails,
              arguments: order,
            ),
          );
        },
      ),
    );
  }

  Widget _buildPastList() {
    // Show full spinner only on initial load (no data fetched yet).
    if (!_pastLoadRequested || (_isPastLoading && _pastOrders.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pastError != null && _pastOrders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              const Text(
                'Failed to load orders',
                style: TextStyle(fontWeight: FontWeight.w600),
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'No past orders found',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadPastOrders,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: _pastOrders.length + (_hasMorePast ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _pastOrders.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _isLoadingMorePast
                    ? const CircularProgressIndicator()
                    : TextButton.icon(
                        onPressed: _loadMorePast,
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('Load More'),
                      ),
              ),
            );
          }
          return _OrderCard(
            order: _pastOrders[index],
            onTap: () => Navigator.of(context).pushNamed(
              AppRoutes.orderDetails,
              arguments: _pastOrders[index],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

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
            _buildInfo(context, Icons.store_rounded, order.storeName),
            _buildInfo(context, Icons.person_rounded, order.customerName),
            _buildInfo(
              context,
              Icons.location_on_rounded,
              order.drop.isNotEmpty ? order.drop : order.deliveryAddress,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (order.estimatedEarnings > 0)
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
                if (order.createdAt != null)
                  Text(
                    _formatDate(order.createdAt!),
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  )
                else if (order.distanceKm > 0)
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

  Widget _buildInfo(BuildContext context, IconData icon, String text) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: scheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]}, $h:$m';
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
      case OrderStatus.returned:
        return Colors.brown;
    }
  }
}

// ---------------------------------------------------------------------------

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  bool _isNavigating = false;

  void _handleTabTap(int index) {
    if (_isNavigating || index == 2) return;
    setState(() => _isNavigating = true);
    if (index == 0) {
      Navigator.of(context).maybePop().whenComplete(
        () {
          if (mounted) setState(() => _isNavigating = false);
        },
      );
    } else if (index == 1) {
      Navigator.of(context)
          .pushReplacement(
            NoAnimRoute(builder: (_) => const MyOrdersScreen()),
          )
          .whenComplete(
            () {
              if (mounted) setState(() => _isNavigating = false);
            },
          );
    } else {
      setState(() => _isNavigating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'More',
      subtitle: 'Quick Access',
      padding: EdgeInsets.zero,
      scrollable: false,
      showBottomNav: true,
      bottomNavIndex: 2,
      onBottomNavTap: _handleTabTap,
      child: _buildMenu(),
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
          AppRoutes.earnings,
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
}
