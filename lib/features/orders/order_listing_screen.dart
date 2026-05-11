import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/models/app_models.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import '../orders_by_location/model/external_delivery.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';

class OrderListingScreen extends StatefulWidget {
  const OrderListingScreen({super.key});

  @override
  State<OrderListingScreen> createState() => _OrderListingScreenState();
}

class _OrderListingScreenState extends State<OrderListingScreen> {
  static const int _pageSize = 8;
  static const Duration _searchDebounce = Duration(milliseconds: 450);

  late final ExternalDeliveryRepository _repository;
  late final PagingController<int, DeliveryOrder> _pagingController;
  final TextEditingController _searchController = TextEditingController();
  AppController? _app;

  // Search state
  String _searchQuery = '';
  List<ExternalDelivery> _searchResults = [];
  bool _searchLoading = false;
  String? _searchError;
  Timer? _debounce;

  // Track which search-result card is being opened
  String? _openingOrderId;

  @override
  void initState() {
    super.initState();
    _repository = ExternalDeliveryRepository();
    _pagingController = PagingController<int, DeliveryOrder>(firstPageKey: 0)
      ..addPageRequestListener(_fetchPage);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = AppScope.of(context);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pagingController.dispose();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  // ── Normal paginated fetch ─────────────────────────────────────────────────

  Future<void> _fetchPage(int pageKey) async {
    final app = _app;
    if (app == null) {
      if (!mounted) return;
      _pagingController.error = 'App not ready';
      return;
    }

    try {
      final orders = await _fetchOrdersEnriched(app, pageKey);
      if (!mounted) return;
      final isLast = orders.length < _pageSize;
      if (isLast) {
        _pagingController.appendLastPage(orders);
      } else {
        _pagingController.appendPage(orders, pageKey + orders.length);
      }
    } catch (e, st) {
      debugPrint('[OrderListing] _fetchPage error: $e');
      debugPrint('[OrderListing] stacktrace: $st');
      if (!mounted) return;
      _pagingController.error = e;
    }
  }

  // Tries one single enriched call (frappe.desk.reportview.get) that returns
  // all fields at once. Falls back to concurrent fetchDetail calls if that
  // endpoint is unavailable or returns an unexpected format.
  Future<List<DeliveryOrder>> _fetchOrdersEnriched(
    AppController app,
    int pageKey,
  ) async {
    try {
      final details = await _repository.fetchPageEnriched(
        limitStart: pageKey,
        limitPageLength: _pageSize,
        filters: <List<dynamic>>[
          <dynamic>['External Delivery', 'status', '=', 'Pending'],
        ],
      );
      return details
          .map((d) => app.buildDeliveryOrderFromDetail(d))
          .toList()
        ..sort((a, b) {
          final c = a.distanceKm.compareTo(b.distanceKm);
          return c != 0 ? c : a.orderId.compareTo(b.orderId);
        });
    } catch (e) {
      debugPrint('[OrderListing] enriched fetch failed, using fallback: $e');
    }

    // Fallback: summary list + concurrent detail fetches (no address resolve).
    final summaries = await _repository.fetchPage(
      limitStart: pageKey,
      limitPageLength: _pageSize,
      orderBy: 'modified desc',
      filters: <List<dynamic>>[
        <dynamic>['External Delivery', 'status', '=', 'Pending'],
      ],
    );
    final results = await Future.wait(
      summaries.map((s) async {
        try {
          final d = await _repository.fetchDetail(s.name, resolveAddress: false);
          return app.buildDeliveryOrderFromDetail(d);
        } catch (e) {
          debugPrint('[OrderListing] detail warn: ${s.name} $e');
          return null;
        }
      }),
    );
    return results.whereType<DeliveryOrder>().toList()
      ..sort((a, b) {
        final c = a.distanceKm.compareTo(b.distanceKm);
        return c != 0 ? c : a.orderId.compareTo(b.orderId);
      });
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  void _onSearchChanged() {
    final q = _searchController.text.trim();
    if (q == _searchQuery) return;
    setState(() {
      _searchQuery = q;
      _searchResults = [];
      _searchError = null;
    });
    _debounce?.cancel();
    if (q.length >= 2) {
      _searchLoading = true;
      _debounce = Timer(_searchDebounce, () => _runSearch(q));
    } else {
      _searchLoading = false;
    }
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _searchLoading = true;
      _searchError = null;
    });
    try {
      // Frappe: AND (status=Pending) AND (name LIKE % OR store_name LIKE % OR customer_name LIKE %)
      final results = await _repository.fetchPage(
        limitStart: 0,
        limitPageLength: 100,
        orderBy: 'modified desc',
        filters: <List<dynamic>>[
          <dynamic>['External Delivery', 'status', '=', 'Pending'],
        ],
        orFilters: <List<dynamic>>[
          <dynamic>['External Delivery', 'name', 'like', '%$query%'],
          <dynamic>['External Delivery', 'store_name', 'like', '%$query%'],
          <dynamic>['External Delivery', 'customer_name', 'like', '%$query%'],
        ],
      );
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searchLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = e.toString().replaceFirst('Exception: ', '');
        _searchLoading = false;
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _searchResults = [];
      _searchError = null;
      _searchLoading = false;
    });
  }

  // Open a search-result card: fetch full detail then navigate.
  Future<void> _openSearchResult(ExternalDelivery summary) async {
    final app = _app;
    if (app == null) return;
    setState(() => _openingOrderId = summary.name);
    try {
      final detail = await _repository.fetchDetail(summary.name);
      final order = app.buildDeliveryOrderFromDetail(detail);
      if (!mounted) return;
      Navigator.of(context).pushNamed(AppRoutes.orderDetails, arguments: order);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load order: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _openingOrderId = null);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool searching = _searchQuery.length >= 2;

    return AppShell(
      title: 'Available Orders',
      subtitle: 'Browse nearby orders before accepting',
      scrollable: false,
      child: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by Order ID, Store or Customer…',
                hintStyle: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.4),
                  fontSize: 13,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: searching
                      ? AppTheme.oceanBlue
                      : scheme.onSurface.withValues(alpha: 0.4),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: scheme.onSurface.withValues(alpha: 0.6),
                        onPressed: _clearSearch,
                      )
                    : null,
                filled: true,
                fillColor: scheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 13,
                  horizontal: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: scheme.onSurface.withValues(alpha: 0.12),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: scheme.onSurface.withValues(alpha: 0.12),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: AppTheme.oceanBlue, width: 1.5),
                ),
              ),
            ),
          ),

          // Search status row
          if (searching)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  if (_searchLoading) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.oceanBlue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Searching…',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ] else if (_searchError != null) ...[
                    Icon(
                      Icons.error_outline,
                      size: 14,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _searchError!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade400,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.oceanBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.oceanBlue.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        '${_searchResults.length} result${_searchResults.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.oceanBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: _clearSearch,
                    child: Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // List area
          Expanded(
            child: searching
                ? _buildSearchView()
                : RefreshIndicator(
                    onRefresh: () async => _pagingController.refresh(),
                    color: Colors.orange,
                    child: _buildPagedList(),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Normal paginated list ──────────────────────────────────────────────────

  Widget _buildPagedList() {
    return PagedListView<int, DeliveryOrder>(
      pagingController: _pagingController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
      builderDelegate: PagedChildBuilderDelegate<DeliveryOrder>(
        firstPageProgressIndicatorBuilder: (_) =>
            const Center(child: CircularProgressIndicator()),
        newPageProgressIndicatorBuilder: (_) => const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: CircularProgressIndicator()),
        ),
        firstPageErrorIndicatorBuilder: (_) =>
            _ErrorState(onRetry: _pagingController.refresh),
        newPageErrorIndicatorBuilder: (_) =>
            _ErrorState(onRetry: _pagingController.retryLastFailedRequest),
        noItemsFoundIndicatorBuilder: (_) => const _EmptyState(),
        itemBuilder: (context, order, index) {
          return _FullOrderCard(
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

  // ── Search results view ────────────────────────────────────────────────────

  Widget _buildSearchView() {
    if (_searchLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchError != null) {
      return _ErrorState(onRetry: () => _runSearch(_searchQuery));
    }

    if (_searchResults.isEmpty) {
      return _SearchEmpty(query: _searchQuery);
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final summary = _searchResults[index];
        final isOpening = _openingOrderId == summary.name;
        return _SearchResultCard(
          summary: summary,
          query: _searchQuery,
          isLoading: isOpening,
          onTap: isOpening ? null : () => _openSearchResult(summary),
        );
      },
    );
  }
}

// ── Full detail card ──────────────────────────────────────────────────────────

class _FullOrderCard extends StatelessWidget {
  const _FullOrderCard({required this.order, required this.onTap});

  final DeliveryOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FrostCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      order.assignmentStatus.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _Row(Icons.store_rounded, 'Store', order.storeName),
              _Row(Icons.person_rounded, 'Customer', order.customerName),
              _Row(Icons.location_on_rounded, 'Drop', order.deliveryAddress),
              _Row(Icons.route_rounded, 'Distance', '${order.distanceKm} km'),
              if (order.estimatedEarnings > 0)
                _Row(
                  Icons.currency_rupee_rounded,
                  'Earnings',
                  'Rs. ${order.estimatedEarnings.toStringAsFixed(0)}',
                ),
              if (order.orderItems.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Text(
                  'Items',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                ...order.orderItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 5,
                          color: scheme.onSurface.withValues(alpha: 0.4),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          'x${item.quantity}  Rs. ${(item.price * item.quantity).toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.oceanBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'View Details',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Lightweight search-result card (summary only) ─────────────────────────────

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.summary,
    required this.query,
    required this.isLoading,
    required this.onTap,
  });

  final ExternalDelivery summary;
  final String query;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FrostCard(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.oceanBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.shopping_bag_rounded,
                    color: AppTheme.oceanBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Highlight(
                        text: summary.name,
                        query: query,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      _Highlight(
                        text: summary.storeName,
                        query: query,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 2),
                      _Highlight(
                        text: summary.customerName,
                        query: query,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.oceanBlue,
                    ),
                  )
                else
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: scheme.onSurface.withValues(alpha: 0.4),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Highlight matching text ───────────────────────────────────────────────────

class _Highlight extends StatelessWidget {
  const _Highlight({
    required this.text,
    required this.query,
    required this.style,
  });

  final String text;
  final String query;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return Text(text, style: style);

    final lower = text.toLowerCase();
    final lq = query.toLowerCase();
    final idx = lower.indexOf(lq);
    if (idx < 0) return Text(text, style: style);

    final ColorScheme scheme = Theme.of(context).colorScheme;
    return RichText(
      text: TextSpan(
        style: style.copyWith(color: scheme.onSurface),
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + query.length),
            style: style.copyWith(
              color: AppTheme.oceanBlue,
              fontWeight: FontWeight.bold,
              backgroundColor: AppTheme.oceanBlue.withValues(alpha: 0.1),
            ),
          ),
          TextSpan(text: text.substring(idx + query.length)),
        ],
      ),
    );
  }
}

// ── Shared row widget ─────────────────────────────────────────────────────────

class _Row extends StatelessWidget {
  const _Row(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 15,
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── Empty / error states ──────────────────────────────────────────────────────

class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 56,
            color: scheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 14),
          Text(
            'No results for "$query"',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different order ID, store name, or customer name.',
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.6),
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.local_shipping_outlined,
            size: 64,
            color: scheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          const Text('No available orders'),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Failed to load orders'),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
