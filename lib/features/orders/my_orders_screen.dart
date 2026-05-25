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

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
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
    final controller = ref.watch(appControllerProvider);
    return AppShell(
      title: 'More',
      padding: EdgeInsets.zero,
      scrollable: false,
      showBottomNav: true,
      bottomNavIndex: 2,
      onBottomNavTap: _handleTabTap,
      child: _buildContent(controller),
    );
  }

  Widget _buildContent(dynamic controller) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _buildProfileCard(controller),
        const SizedBox(height: 24),
        _buildSection('Earnings & Trips', [
          _sectionTile(
            Icons.monetization_on_rounded,
            'Earnings Summary',
            AppRoutes.earnings,
          ),
          _divider(),
          _sectionTile(
            Icons.analytics_rounded,
            'External Delivery Trips',
            AppRoutes.externalDeliveryTripList,
            isNew: true,
          ),
          _divider(),
          _sectionTile(
            Icons.history_rounded,
            'Available Orders',
            AppRoutes.orderListing,
          ),
        ]),
        const SizedBox(height: 20),
        _buildSection('Account', [
          _sectionTile(
            Icons.description_rounded,
            'Documents / KYC',
            AppRoutes.kycDocuments,
          ),
          _divider(),
          _sectionTile(
            Icons.car_rental_rounded,
            'Vehicle Details',
            AppRoutes.vehicleDetails,
          ),
          _divider(),
          _sectionTile(
            Icons.account_balance_rounded,
            'Bank Details',
            AppRoutes.bankSetup,
          ),
          _divider(),
          _sectionTile(
            Icons.settings_rounded,
            'Settings',
            AppRoutes.settings,
          ),
        ]),
        const SizedBox(height: 20),
        _buildSection('Support', [
          _sectionTile(
            Icons.help_outline_rounded,
            'Help & Support',
            AppRoutes.settings,
          ),
          _divider(),
          _sectionTile(
            Icons.privacy_tip_outlined,
            'Terms & Privacy',
            AppRoutes.settings,
          ),
        ]),
        const SizedBox(height: 24),
        _logoutItem(),
      ],
    );
  }

  Widget _buildProfileCard(dynamic controller) {
    final String name =
        (controller.profile?.fullName as String?) ?? 'Partner';
    final String phone = (controller.profile?.mobile as String?) ?? '';
    final bool isOnline = controller.isOnline as bool;
    final String partnerId = (controller.driverName as String?) ?? '';
    final int totalDeliveries =
        controller.performance.totalDeliveries as int;
    final double rating = controller.performance.rating as double;
    final double weekEarnings = controller.earnings.week as double;

    final parts = name.trim().split(RegExp(r'\s+'));
    final String initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : name.isNotEmpty
            ? name[0].toUpperCase()
            : 'P';

    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.profile),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.oceanBlue, Color(0xFF0d2f5e)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppTheme.oceanBlue.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isOnline
                                  ? const Color(0xFF22C55E)
                                  : Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isOnline ? 'Online' : 'Offline',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          phone,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 13,
                          ),
                        ),
                      ],
                      if (partnerId.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'ID: $partnerId',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _statChip(label: 'Deliveries', value: '$totalDeliveries'),
                const SizedBox(width: 8),
                _statChip(
                  label: 'Rating',
                  value: rating.toStringAsFixed(1),
                  icon: Icons.star_rounded,
                ),
                const SizedBox(width: 8),
                _statChip(
                  label: 'This Week',
                  value: '₹${weekEarnings.toStringAsFixed(0)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip({
    required String label,
    required String value,
    IconData? icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 13),
                  const SizedBox(width: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            else
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> tiles) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface.withValues(alpha: 0.45),
              letterSpacing: 0.8,
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: tiles),
        ),
      ],
    );
  }

  Widget _divider() {
    return Divider(
      height: 1,
      indent: 56,
      endIndent: 16,
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
    );
  }

  Widget _sectionTile(
    IconData icon,
    String label,
    String route, {
    bool isNew = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.oceanBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.oceanBlue, size: 18),
      ),
      title: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          if (isNew) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.mint,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'NEW',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: scheme.onSurface.withValues(alpha: 0.3),
        size: 20,
      ),
      onTap: () => Navigator.of(context).pushNamed(route),
    );
  }

  Future<void> _confirmAndLogout() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Log out?'),
          content: const Text('You will need to sign in again to continue.'),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Log out'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await ref.read(appControllerProvider).logout();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  Widget _logoutItem() {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.red.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.logout_rounded, color: Colors.red, size: 18),
        ),
        title: const Text(
          'Log out',
          style: TextStyle(
            fontSize: 14,
            color: Colors.red,
            fontWeight: FontWeight.w600,
          ),
        ),
        onTap: _confirmAndLogout,
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
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
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
