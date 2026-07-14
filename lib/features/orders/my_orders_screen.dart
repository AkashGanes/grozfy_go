import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/providers.dart';
import '../../core/theme/context_colors.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/authed_network_image.dart';
import '../dashboard/widgets/dashboard_colors.dart';
import '../dashboard/widgets/section_card.dart';
import '../orders_by_location/model/external_delivery.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';
import '../stats/providers/stats_providers.dart';

class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> {
  int _selectedTab = 0;
  bool _isNavigating = false;

  final ExternalDeliveryRepository _repo = ExternalDeliveryRepository();

  List<ExternalDelivery> _activeOrders = [];
  bool _isActiveLoading = true;
  String? _activeError;
  Future<void>? _activeFuture;

  List<ExternalDelivery> _pastOrders = [];
  bool _isPastLoading = true;
  bool _isLoadingMorePast = false;
  bool _hasMorePast = false;
  int _pastLimitStart = 0;
  static const int _pastPageSize = 20;
  String? _pastError;
  Future<void>? _pastFuture;
  bool _pastLoadRequested = false;
  int? _pastTotalCount;
  final ScrollController _pastScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadActiveOrders();
    _loadPastOrders();
    _loadPastCount();
    _pastScrollController.addListener(_onPastScroll);
  }

  @override
  void dispose() {
    _pastScrollController
      ..removeListener(_onPastScroll)
      ..dispose();
    super.dispose();
  }

  void _onPastScroll() {
    final pos = _pastScrollController.position;
    if (pos.extentAfter < 300 && _hasMorePast && !_isLoadingMorePast) {
      _loadMorePast();
    }
  }

  // Convert an app-state DeliveryOrder to ExternalDelivery for unified display.
  ExternalDelivery _orderToSummary(DeliveryOrder o) {
    String statusStr;
    switch (o.orderStatus) {
      case OrderStatus.accepted:
        statusStr = 'Added to Trip';
        break;
      case OrderStatus.reachedPickup:
        statusStr = 'Reached Pickup';
        break;
      case OrderStatus.pickedUp:
        statusStr = 'Picked Up';
        break;
      case OrderStatus.outForDelivery:
        statusStr = 'Out for Delivery';
        break;
      case OrderStatus.delivered:
        statusStr = 'Delivered';
        break;
      case OrderStatus.failed:
        statusStr = 'Failed';
        break;
      case OrderStatus.cancelled:
        statusStr = 'Cancelled';
        break;
      case OrderStatus.returned:
        statusStr = 'Returned';
        break;
      default:
        statusStr = 'Pending';
    }
    final modified = o.acceptedAt?.toString() ?? o.createdAt?.toString() ?? '';
    return ExternalDelivery(
      name: o.orderId,
      storeUrl: o.storeId,
      storeName: o.storeName,
      customerName: o.customerName,
      status: statusStr,
      creation: o.createdAt?.toString() ?? '',
      modified: modified,
      deliveryAddress: o.deliveryAddress,
    );
  }

  // Reverse of _orderToSummary: build a DeliveryOrder from a fetched
  // ExternalDelivery summary. Used as a fallback for the Active tab when an
  // order isn't present in the (capped) app-state active orders list, so
  // "View Details" always navigates instead of silently doing nothing.
  DeliveryOrder _summaryToOrder(ExternalDelivery order) {
    final OrderStatus status = switch (order.status) {
      'Added to Trip' => OrderStatus.accepted,
      'Reached Pickup' => OrderStatus.reachedPickup,
      'Picked Up' => OrderStatus.pickedUp,
      'Out for Delivery' => OrderStatus.outForDelivery,
      'Delivered' => OrderStatus.delivered,
      'Failed' => OrderStatus.failed,
      'Cancelled' => OrderStatus.cancelled,
      'Returned' => OrderStatus.returned,
      _ => OrderStatus.pending,
    };
    return DeliveryOrder(
      orderId: order.name,
      customerName: order.customerName,
      customerPhone: '',
      deliveryAddress: order.deliveryAddress ?? '',
      storeId: order.storeUrl,
      storeName: order.storeName,
      storeContact: '',
      storeAddress: '',
      orderItems: const [],
      orderStatus: status,
      latitude: 0,
      longitude: 0,
      failureReasonCode: order.failureReasonCode,
      deliveryNotes: order.deliveryNotes,
      completedAt: DateTime.tryParse(order.modified),
    );
  }

  Future<void> _loadPastOrders() async {
    if (_pastFuture != null) return;
    _pastLoadRequested = true;
    _pastFuture = _doLoadPast();
    await _pastFuture;
    _pastFuture = null;
  }

  Future<void> _loadPastCount() async {
    try {
      final count = await _repo.fetchPastOrdersCountForDriver();
      if (mounted) setState(() => _pastTotalCount = count);
    } catch (_) {}
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
      if (mounted) {
        setState(() {
          _activeOrders = summaries;
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
      if (mounted) {
        setState(() {
          _pastOrders = summaries;
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
      if (mounted) {
        final existingNames = _pastOrders.map((o) => o.name).toSet();
        final fresh = summaries.where((o) => existingNames.add(o.name)).toList();
        setState(() {
          _pastOrders = [..._pastOrders, ...fresh];
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
    final appActiveOrders = ref.watch(appControllerProvider).activeOrders;
    final List<ExternalDelivery> activeOrders = _buildActiveOrders(appActiveOrders);
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
          _buildTabBar(activeOrders.length),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _selectedTab == 0
                  ? KeyedSubtree(
                      key: const ValueKey('active'),
                      child: _buildActiveList(activeOrders, appActiveOrders),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('past'),
                      child: _buildPastList(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Merge the in-progress order from app state with the fetched active list,
  /// de-duplicating by order id. The previous code showed *either* the app's
  /// active order *or* the fetched list — never both — so an in-progress order
  /// vanished as soon as the fetch returned. Showing both without de-duping
  /// would render (and key) the same order twice, tripping a duplicate-key
  /// assertion; this keeps a single, ordered, unique list.
  List<ExternalDelivery> _buildActiveOrders(List<DeliveryOrder> appActiveOrders) {
    final seen = <String>{};
    final merged = <ExternalDelivery>[];
    void add(ExternalDelivery order) {
      if (order.name.isNotEmpty && seen.add(order.name)) merged.add(order);
    }
    // App state orders show immediately (from cache); fetched list refreshes them.
    for (final order in appActiveOrders) {
      add(_orderToSummary(order));
    }
    for (final order in _activeOrders) {
      add(order);
    }
    return merged;
  }

  /// Wraps a non-list message (empty / error state) so pull-to-refresh still
  /// works: [RefreshIndicator] requires a scrollable descendant, so the message
  /// is placed inside an always-scrollable viewport sized to fill the area.
  Widget _refreshable(Future<void> Function() onRefresh, Widget child) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.onSurface.withValues(alpha: 0.04),
          ),
          child: Icon(
            icon,
            size: 44,
            color: scheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }

  Widget _errorState({
    required String message,
    String? detail,
    required Future<void> Function() onRetry,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline_rounded, size: 48, color: context.danger),
        const SizedBox(height: 12),
        Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        if (detail != null) ...[
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Retry'),
        ),
      ],
    );
  }

  Widget _buildTabBar(int activeCount) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outline.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            _tabSegment(
              index: 0,
              label: 'Active',
              count: activeCount,
              onTap: () {
                if (_selectedTab != 0) setState(() => _selectedTab = 0);
              },
            ),
            _tabSegment(
              index: 1,
              label: 'Past',
              count: _pastTotalCount ?? (_pastOrders.isNotEmpty ? _pastOrders.length : null),
              onTap: () {
                if (_selectedTab != 1) setState(() => _selectedTab = 1);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabSegment({
    required int index,
    required String label,
    required int? count,
    required VoidCallback onTap,
  }) {
    final bool selected = _selectedTab == index;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? context.scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: context.scheme.primary.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : scheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.22)
                        : scheme.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : scheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveList(
    List<ExternalDelivery> activeOrders,
    List<DeliveryOrder> appActiveOrders,
  ) {
    if (_activeError != null && activeOrders.isEmpty) {
      return _refreshable(
        _loadActiveOrders,
        _errorState(
          message: 'Failed to load active orders',
          detail: _activeError,
          onRetry: _loadActiveOrders,
        ),
      );
    }
    if (activeOrders.isEmpty && _isActiveLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (activeOrders.isEmpty) {
      return _refreshable(
        _loadActiveOrders,
        _emptyState(
          icon: Icons.local_shipping_outlined,
          title: 'No active orders',
          subtitle: 'New deliveries assigned to you will appear here.',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadActiveOrders,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        itemCount: activeOrders.length,
        itemBuilder: (context, index) {
          final order = activeOrders[index];
          return _OrderCard(
            key: ValueKey('active_${order.name}'),
            order: order,
            showDate: false,
            onTap: () {
              final matches = appActiveOrders
                  .where((o) => o.orderId == order.name);
              final DeliveryOrder deliveryOrder = matches.isNotEmpty
                  ? matches.first
                  : _summaryToOrder(order);
              Navigator.of(context).pushNamed(
                AppRoutes.orderDetails,
                arguments: deliveryOrder,
              );
            },
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
      return _refreshable(
        _loadPastOrders,
        _errorState(
          message: 'Failed to load orders',
          detail: _pastError,
          onRetry: _loadPastOrders,
        ),
      );
    }
    if (_pastOrders.isEmpty) {
      return _refreshable(
        _loadPastOrders,
        _emptyState(
          icon: Icons.history_rounded,
          title: 'No past orders found',
          subtitle: 'Completed and cancelled deliveries will show up here.',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadPastOrders,
      child: ListView.builder(
        controller: _pastScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        itemCount: _pastOrders.length + (_isLoadingMorePast ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _pastOrders.length) {
            return const Padding(
              key: ValueKey('past_loading_more'),
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final order = _pastOrders[index];
          return _OrderCard(
            key: ValueKey('past_${order.name}'),
            order: order,
            onTap: () {
              final OrderStatus status = switch (order.status) {
                'Delivered' => OrderStatus.delivered,
                'Cancelled' => OrderStatus.cancelled,
                'Failed' => OrderStatus.failed,
                'Returned' => OrderStatus.returned,
                'Return Initiated' => OrderStatus.returned,
                _ => OrderStatus.delivered,
              };
              final deliveryOrder = DeliveryOrder(
                orderId: order.name,
                customerName: order.customerName,
                customerPhone: '',
                deliveryAddress: order.deliveryAddress ?? '',
                storeId: order.storeUrl,
                storeName: order.storeName,
                storeContact: '',
                storeAddress: '',
                orderItems: const [],
                orderStatus: status,
                latitude: 0,
                longitude: 0,
                failureReasonCode: order.failureReasonCode,
                deliveryNotes: order.deliveryNotes,
                completedAt: DateTime.tryParse(order.modified),
              );
              Navigator.of(context).pushNamed(
                AppRoutes.orderDetails,
                arguments: deliveryOrder,
              );
            },
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
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(appControllerProvider.notifier)
          .fetchLoggedInEmployeeDriverProfile();
    });
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
  }

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
    final deliveriesAsync = ref.watch(deliveredOrderCountProvider);
    return AppShell(
      title: 'More',
      padding: EdgeInsets.zero,
      scrollable: false,
      showBottomNav: true,
      bottomNavIndex: 2,
      onBottomNavTap: _handleTabTap,
      child: _buildContent(controller, deliveriesAsync),
    );
  }

  Widget _buildContent(dynamic controller, AsyncValue<int> deliveriesAsync) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _buildProfileCard(controller, deliveriesAsync)
            .animate()
            .fadeIn(duration: 280.ms)
            .slideY(begin: 0.04, end: 0),
        const SizedBox(height: 24),
        _buildSection(
          'Earnings & Trips',
          [
            _tile(
              icon: Icons.payments_rounded,
              label: 'My Settlement',
              route: AppRoutes.codSettlement,
              color: const Color(0xFF1AB36A),
            ),
            _divider(),
            _tile(
              icon: Icons.monetization_on_rounded,
              label: 'Earnings Summary',
              route: AppRoutes.earnings,
              color: const Color(0xFF2D6CDF),
            ),
            _divider(),
            _tile(
              icon: Icons.route_rounded,
              label: 'External Delivery Trips',
              route: AppRoutes.externalDeliveryTripList,
              color: const Color(0xFF7C3AED),
            ),
            _divider(),
            _tile(
              icon: Icons.list_alt_rounded,
              label: 'Available Orders',
              route: AppRoutes.orderListing,
              color: const Color(0xFF0891B2),
            ),
            _divider(),
            _tile(
              icon: Icons.inventory_2_rounded,
              label: 'Return Pickups',
              route: AppRoutes.pickupPool,
              color: const Color(0xFFE65100),
            ),
          ],
        ).animate().fadeIn(duration: 280.ms, delay: 60.ms).slideY(begin: 0.04, end: 0),
        const SizedBox(height: 20),
        _buildSection(
          'Account',
          [
            _tile(
              icon: Icons.shield_outlined,
              label: 'Documents / KYC',
              route: AppRoutes.kycDocuments,
              color: const Color(0xFF7C3AED),
            ),
            _divider(),
            _tile(
              icon: Icons.two_wheeler_rounded,
              label: 'Vehicle Details',
              route: AppRoutes.vehicleDetails,
              color: const Color(0xFF1AB36A),
            ),
            _divider(),
            _tile(
              icon: Icons.account_balance_outlined,
              label: 'Bank Details',
              route: AppRoutes.bankSetup,
              color: const Color(0xFF2D6CDF),
            ),
            _divider(),
            _tile(
              icon: Icons.settings_outlined,
              label: 'Settings',
              route: AppRoutes.settings,
              color: context.textSecondary,
            ),
            _divider(),
            _tile(
              icon: Icons.lock_rounded,
              label: 'Security',
              route: AppRoutes.security,
              color: const Color(0xFF1AB36A),
            ),
          ],
        ).animate().fadeIn(duration: 280.ms, delay: 120.ms).slideY(begin: 0.04, end: 0),
        const SizedBox(height: 20),
        _buildSection(
          'Support',
          [
            _tile(
              icon: Icons.help_outline_rounded,
              label: 'Help & Support',
              route: AppRoutes.support,
              color: const Color(0xFFF6A623),
            ),
            _divider(),
            _tile(
              icon: Icons.privacy_tip_outlined,
              label: 'Terms & Privacy',
              route: AppRoutes.settings,
              color: context.textSecondary,
            ),
          ],
        ).animate().fadeIn(duration: 280.ms, delay: 180.ms).slideY(begin: 0.04, end: 0),
        const SizedBox(height: 12),
        _logoutItem()
            .animate()
            .fadeIn(duration: 280.ms, delay: 240.ms)
            .slideY(begin: 0.04, end: 0),
        if (_appVersion.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Center(
              child: Text(
                'Version $_appVersion',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ).animate().fadeIn(duration: 280.ms, delay: 280.ms),
      ],
    );
  }

  // ── Profile card ──────────────────────────────────────────────────────────

  Widget _buildProfileCard(dynamic controller, AsyncValue<int> deliveriesAsync) {
    final String name =
        (controller.profile?.fullName as String?) ?? 'Partner';
    final String phone = (controller.profile?.mobile as String?) ?? '';
    final bool isOnline = controller.isOnline as bool;
    final String partnerId = (controller.driverName as String?) ?? '';
    final double rating = controller.performance.rating as double;

    final parts = name.trim().split(RegExp(r'\s+'));
    final String initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : name.isNotEmpty
            ? name[0].toUpperCase()
            : 'P';

    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.profile),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A3FA6).withValues(alpha: 0.28),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              // Gradient background — matches ProfileProgressCard
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1C4E80), Color(0xFF0C2A4A)],
                    ),
                  ),
                ),
              ),
              // Decorative circles
              Positioned(
                right: -50,
                top: -40,
                child: _decorCircle(160, 0.10),
              ),
              Positioned(
                right: 70,
                bottom: -55,
                child: _decorCircle(110, 0.07),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                child: Column(
                  children: [
                    // Avatar row
                    Row(
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.45),
                              width: 2.5,
                            ),
                          ),
                          child: ClipOval(
                            child: _buildAvatar(controller, initials),
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
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _onlineBadge(isOnline),
                                ],
                              ),
                              if (phone.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  phone,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.78),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                              if (partnerId.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Partner ID: $partnerId',
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
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white.withValues(alpha: 0.45),
                          size: 16,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Stats chips
                    Row(
                      children: [
                        _statChip(
                          icon: Icons.local_shipping_outlined,
                          iconBg: Colors.white.withValues(alpha: 0.18),
                          value: deliveriesAsync.when(
                            data: (c) => '$c',
                            loading: () => '…',
                            error: (e, s) => '—',
                          ),
                          label: 'Deliveries',
                          isLoading: deliveriesAsync.isLoading,
                        ),
                        const SizedBox(width: 10),
                        _statChip(
                          icon: Icons.star_rounded,
                          iconBg: const Color(0xFFF6A623).withValues(alpha: 0.28),
                          iconColor: const Color(0xFFF6A623),
                          value: (controller.profileDetailsLoading as bool)
                              ? '…'
                              : (rating > 0 ? rating.toStringAsFixed(1) : '—'),
                          label: 'Rating',
                          isLoading: controller.profileDetailsLoading as bool,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _decorCircle(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha),
        ),
      );

  Widget _buildAvatar(dynamic controller, String initials) {
    final String? localPath = controller.profileImagePath as String?;
    final String? serverUrl = controller.serverProfileImageFullUrl as String?;
    final Map<String, String> headers =
        controller.buildAuthHeaders() as Map<String, String>;
    final fallback = _initialsAvatar(initials);

    if (localPath != null && File(localPath).existsSync()) {
      return Image.file(
        File(localPath),
        fit: BoxFit.cover,
        width: 62,
        height: 62,
        errorBuilder: (context, e, s) => fallback,
      );
    }
    if (serverUrl != null && serverUrl.isNotEmpty) {
      if (headers.isNotEmpty) {
        return AuthedNetworkImage(
          url: serverUrl,
          authHeaders: headers,
          size: 62,
          fallback: fallback,
        );
      }
      return Image.network(
        serverUrl,
        fit: BoxFit.cover,
        width: 62,
        height: 62,
        errorBuilder: (context, e, s) => fallback,
      );
    }
    return fallback;
  }

  Widget _initialsAvatar(String initials) => Container(
        color: Colors.white.withValues(alpha: 0.18),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Widget _onlineBadge(bool isOnline) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isOnline
              ? const Color(0xFF1AB36A)
              : Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              isOnline ? 'Online' : 'Offline',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );

  Widget _statChip({
    required IconData icon,
    required String value,
    required String label,
    required Color iconBg,
    Color iconColor = Colors.white,
    bool isLoading = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 17),
            ),
            const SizedBox(height: 8),
            isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  )
                : Text(
                    value,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  Widget _buildSection(String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: DashColors.textSecondary(context),
              letterSpacing: 0.8,
            ),
          ),
        ),
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          borderRadius: 18,
          child: Column(children: tiles),
        ),
      ],
    );
  }

  Widget _divider() => Divider(
        height: 1,
        indent: 62,
        endIndent: 16,
        color: DashColors.cardBorder(context).withValues(alpha: 0.7),
      );

  Widget _tile({
    required IconData icon,
    required String label,
    required String route,
    required Color color,
    bool isNew = false,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 19),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DashColors.textPrimary(context),
              ),
            ),
          ),
          if (isNew)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: context.successContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'NEW',
                style: TextStyle(
                  color: context.success,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: DashColors.textSecondary(context).withValues(alpha: 0.5),
        size: 20,
      ),
      onTap: () => Navigator.of(context).pushNamed(route),
    );
  }

  // ── Logout ────────────────────────────────────────────────────────────────

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
                      backgroundColor:
                          Theme.of(dialogContext).colorScheme.error,
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
    if (confirmed != true || !mounted) return;
    // Navigate to login *before* awaiting logout(). logout() synchronously
    // clears the in-memory session and notifies listeners — which rebuilds the
    // dashboard/more screens in an empty "Partner / 0% profile / Offline" state
    // — and only then awaits slow local cleanup (home-widget reset, secure
    // storage, SharedPreferences). Awaiting that before navigating leaves the
    // cleared screen on display until cleanup finishes. Pushing login first
    // hides the teardown behind the login screen. Capture the controller and
    // navigator up front because this push disposes the screen, after which
    // `ref`/`context` are no longer usable.
    final NavigatorState navigator = Navigator.of(context);
    final app = ref.read(appControllerProvider);
    navigator.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    await app.logout();
  }

  Widget _logoutItem() {
    return SectionCard(
      padding: EdgeInsets.zero,
      borderRadius: 18,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: context.dangerContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.logout_rounded,
            color: context.danger,
            size: 19,
          ),
        ),
        title: Text(
          'Log out',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.danger,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: context.danger.withValues(alpha: 0.4),
          size: 20,
        ),
        onTap: _confirmAndLogout,
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _OrderCard extends StatelessWidget {
  const _OrderCard({super.key, required this.order, this.onTap, this.showDate = true});
  final ExternalDelivery order;
  final VoidCallback? onTap;
  final bool showDate;

  String _formatDate(String raw) {
    if (raw.length < 10) return raw;
    final parts = raw.substring(0, 10).split('-');
    if (parts.length != 3) return raw.substring(0, 10);
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final Color cardBg = context.cardColor;
    final Color cardBorder = context.borderSubtle;
    final Color textPrimary = context.textPrimary;
    final Color textSecondary = context.textSecondary;
    final Color accent = context.scheme.primary;
    final statusColor = order.status.statusColorIn(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Material(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  border: Border.all(color: cardBorder),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: context.shadowColor,
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Order ID + status badge
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  order.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  order.status,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: statusColor,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _CardMetaRow(
                            icon: Icons.store_rounded,
                            iconColor: const Color(0xFF2D6CDF),
                            iconBg: context.infoContainer,
                            label: 'Store',
                            value: order.storeName.isNotEmpty
                                ? order.storeName
                                : '—',
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                          _CardMetaRow(
                            icon: Icons.person_rounded,
                            iconColor: const Color(0xFF1AB36A),
                            iconBg: context.successContainer,
                            label: 'Customer',
                            value: order.customerName.isNotEmpty
                                ? order.customerName
                                : '—',
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                          _CardMetaRow(
                            icon: Icons.location_on_rounded,
                            iconColor: const Color(0xFF7C3AED),
                            iconBg: context.isDark
                                ? const Color(0xFF2D2148)
                                : const Color(0xFFEFE9FE),
                            label: 'Drop',
                            value: (order.deliveryAddress?.isNotEmpty == true)
                                ? order.deliveryAddress!
                                : '—',
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                          if (showDate)
                            _CardMetaRow(
                              icon: Icons.schedule_rounded,
                              iconColor: const Color(0xFFF38B19),
                              iconBg: context.isDark
                                  ? const Color(0xFF3A2613)
                                  : const Color(0xFFFFEFDA),
                              label: 'Date',
                              value: _formatDate(order.modified),
                              labelColor: textSecondary,
                              valueColor: textPrimary,
                            ),
                        ],
                      ),
                    ),
                    // View Details button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Material(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: onTap,
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 48,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Text(
                                  'View Details',
                                  style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                Positioned(
                                  right: 14,
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    color: accent,
                                    size: 22,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Left accent bar
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: IgnorePointer(
                  child: ColoredBox(color: statusColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardMetaRow extends StatelessWidget {
  const _CardMetaRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 14, color: iconColor),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: labelColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: valueColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
