import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
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
              isNew: true,
            ),
            _divider(),
            _tile(
              icon: Icons.list_alt_rounded,
              label: 'Available Orders',
              route: AppRoutes.orderListing,
              color: const Color(0xFF0891B2),
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
              color: const Color(0xFF6B7280),
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
              route: AppRoutes.settings,
              color: const Color(0xFFF6A623),
            ),
            _divider(),
            _tile(
              icon: Icons.privacy_tip_outlined,
              label: 'Terms & Privacy',
              route: AppRoutes.settings,
              color: const Color(0xFF6B7280),
            ),
          ],
        ).animate().fadeIn(duration: 280.ms, delay: 180.ms).slideY(begin: 0.04, end: 0),
        const SizedBox(height: 24),
        _logoutItem()
            .animate()
            .fadeIn(duration: 280.ms, delay: 240.ms)
            .slideY(begin: 0.04, end: 0),
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
                          value: rating.toStringAsFixed(1),
                          label: 'Rating',
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
                color: const Color(0xFF1AB36A).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'NEW',
                style: TextStyle(
                  color: Color(0xFF118A52),
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
    return SectionCard(
      padding: EdgeInsets.zero,
      borderRadius: 18,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFE8384F).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.logout_rounded,
            color: Color(0xFFE8384F),
            size: 19,
          ),
        ),
        title: const Text(
          'Log out',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFFB7283A),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: const Color(0xFFE8384F).withValues(alpha: 0.4),
          size: 20,
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
