import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/models/app_models.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/app_toast.dart';
import '../kyc/widgets/kyc_form_widgets.dart';
import '../orders_by_location/model/external_delivery.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';

// ── Paged list item types ─────────────────────────────────────────────────────

sealed class _ListItem {}

class _HeaderItem extends _ListItem {
  _HeaderItem(this.storeName);
  final String storeName;
}

class _OrderItem extends _ListItem {
  _OrderItem(this.order);
  final DeliveryOrder order;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class OrderListingScreen extends StatefulWidget {
  const OrderListingScreen({super.key});

  @override
  State<OrderListingScreen> createState() => _OrderListingScreenState();
}

class _OrderListingScreenState extends State<OrderListingScreen> {
  static const int _pageSize = 8;
  static const Duration _searchDebounce = Duration(milliseconds: 450);

  late final ExternalDeliveryRepository _repository;
  late final PagingController<int, _ListItem> _pagingController;
  final TextEditingController _searchController = TextEditingController();
  AppController? _app;

  // Search state
  String _searchQuery = '';
  List<ExternalDelivery> _searchResults = [];
  bool _searchLoading = false;
  String? _searchError;
  Timer? _debounce;

  // Store filter state
  String? _selectedStore;

  // Grouping tracker — reset when a new page-0 fetch begins
  String? _lastGroupStore;

  // Track which search-result card is being opened
  String? _openingOrderId;

  @override
  void initState() {
    super.initState();
    _repository = ExternalDeliveryRepository();
    _pagingController = PagingController<int, _ListItem>(firstPageKey: 0)
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

  // ── Store picker ───────────────────────────────────────────────────────────

  Future<void> _showStorePicker() async {
    List<String> stores = [];
    bool loading = true;
    bool fetchStarted = false;

    await showAppBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final ColorScheme scheme = Theme.of(ctx).colorScheme;
            if (loading && !fetchStarted) {
              fetchStarted = true;
              _repository.fetchStoreNames().then((names) {
                setModal(() {
                  stores = names;
                  loading = false;
                });
              }).catchError((_) {
                setModal(() => loading = false);
              });
            }

            return AppBottomSheet(
              title: 'Filter by Store',
              subtitle:
                  'Pending orders will be filtered by your selected store.',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.oceanBlue,
                        ),
                      ),
                    )
                  else if (stores.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No stores found',
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: stores.length + 1,
                        separatorBuilder: (context, _) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) {
                          if (i == 0) {
                            final selected = _selectedStore == null;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.public_rounded,
                                color: selected
                                    ? AppTheme.oceanBlue
                                    : Colors.black38,
                              ),
                              title: Text(
                                'All Stores',
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected
                                      ? AppTheme.oceanBlue
                                      : scheme.onSurface,
                                ),
                              ),
                              trailing: selected
                                  ? const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppTheme.oceanBlue,
                                    )
                                  : null,
                              onTap: () {
                                Navigator.of(ctx).pop();
                                if (_selectedStore != null) {
                                  setState(() => _selectedStore = null);
                                  _lastGroupStore = null;
                                  _pagingController.refresh();
                                }
                              },
                            );
                          }

                          final store = stores[i - 1];
                          final selected = _selectedStore == store;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.store_rounded,
                              color: selected
                                  ? AppTheme.oceanBlue
                                  : scheme.onSurface.withValues(alpha: 0.4),
                            ),
                            title: Text(
                              store,
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? AppTheme.oceanBlue
                                    : scheme.onSurface,
                              ),
                            ),
                            trailing: selected
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppTheme.oceanBlue,
                                  )
                                : null,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              if (_selectedStore != store) {
                                setState(() => _selectedStore = store);
                                _lastGroupStore = null;
                                _pagingController.refresh();
                              }
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Normal paginated fetch ─────────────────────────────────────────────────

  Future<void> _fetchPage(int pageKey) async {
    final app = _app;
    if (app == null) {
      if (!mounted) return;
      _pagingController.error = 'App not ready';
      return;
    }

    // Reset grouping tracker at the start of each new list
    if (pageKey == 0) _lastGroupStore = null;

    try {
      final orders = await _fetchOrdersEnriched(app, pageKey);
      if (!mounted) return;

      final items = <_ListItem>[];
      for (final order in orders) {
        if (order.storeName != _lastGroupStore) {
          items.add(_HeaderItem(order.storeName));
          _lastGroupStore = order.storeName;
        }
        items.add(_OrderItem(order));
      }

      final isLast = orders.length < _pageSize;
      if (isLast) {
        _pagingController.appendLastPage(items);
      } else {
        _pagingController.appendPage(items, pageKey + orders.length);
      }
    } catch (e, st) {
      debugPrint('[OrderListing] _fetchPage error: $e');
      debugPrint('[OrderListing] stacktrace: $st');
      if (!mounted) return;
      _pagingController.error = e;
    }
  }

  Future<List<DeliveryOrder>> _fetchOrdersEnriched(
    AppController app,
    int pageKey,
  ) async {
    final storeFilter = _selectedStore != null && _selectedStore!.isNotEmpty
        ? [<dynamic>['External Delivery', 'store_name', '=', _selectedStore]]
        : <List<dynamic>>[];

    try {
      final details = await _repository.fetchPageEnriched(
        limitStart: pageKey,
        limitPageLength: _pageSize,
        orderBy: 'store_name asc, modified desc',
        filters: <List<dynamic>>[
          <dynamic>['External Delivery', 'status', '=', 'Pending'],
          ...storeFilter,
        ],
      );
      return details.map((d) => app.buildDeliveryOrderFromDetail(d)).toList();
    } catch (e) {
      debugPrint('[OrderListing] enriched fetch failed, using fallback: $e');
    }

    // Fallback: summary list + concurrent detail fetches (no address resolve).
    final summaries = await _repository.fetchPage(
      limitStart: pageKey,
      limitPageLength: _pageSize,
      storeName: _selectedStore,
      orderBy: 'store_name asc, modified desc',
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
    return results.whereType<DeliveryOrder>().toList();
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
      final results = await _repository.fetchPage(
        limitStart: 0,
        limitPageLength: 100,
        orderBy: 'modified desc',
        filters: <List<dynamic>>[
          <dynamic>['External Delivery', 'status', '=', 'Pending'],
          if (_selectedStore != null)
            <dynamic>['External Delivery', 'store_name', '=', _selectedStore],
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
      if (!context.mounted) return;
      AppToast.show(context, 'Could not load order: $e');
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
      subtitle: _selectedStore ?? 'All Stores',
      scrollable: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.store_rounded, color: AppTheme.nightBlue),
          tooltip: 'Filter by store',
          onPressed: _showStorePicker,
        ),
      ],
      child: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: KycSearchInput(
              controller: _searchController,
              hint: 'Search by Order ID, Store or Customer…',
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
                    onRefresh: () async {
                      _lastGroupStore = null;
                      _pagingController.refresh();
                    },
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
    return PagedListView<int, _ListItem>(
      pagingController: _pagingController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
      builderDelegate: PagedChildBuilderDelegate<_ListItem>(
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
        noItemsFoundIndicatorBuilder: (_) =>
            _EmptyState(storeName: _selectedStore),
        itemBuilder: (context, item, index) {
          if (item is _HeaderItem) {
            return _StoreHeaderWidget(storeName: item.storeName);
          }
          final order = (item as _OrderItem).order;
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

// ── Store section header ──────────────────────────────────────────────────────

class _StoreHeaderWidget extends StatelessWidget {
  const _StoreHeaderWidget({required this.storeName});

  final String storeName;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1A2C4F)
                  : const Color(0xFFE5EEFB),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.store_rounded,
              size: 15,
              color: Color(0xFF2D6CDF),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              storeName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? const Color(0xFFF2F4F7)
                    : const Color(0xFF101828),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark ? const Color(0xFF1B1E2A) : Colors.white;
    final Color cardBorder =
        isDark ? const Color(0xFF2A2F3D) : const Color(0xFFE4E7EC);
    final Color textPrimary =
        isDark ? const Color(0xFFF2F4F7) : const Color(0xFF101828);
    final Color textSecondary =
        isDark ? const Color(0xFFA4ABB8) : const Color(0xFF667085);
    const Color accent = Color(0xFF1F5FE8);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            InkWell(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  border: Border.all(color: cardBorder),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: isDark ? 0.25 : 0.04),
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
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  order.orderId,
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
                                  color: const Color(0xFFFEF3E2),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: const Text(
                                  'UNASSIGNED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFB87707),
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _MetaRow(
                            icon: Icons.store_rounded,
                            iconColor: const Color(0xFF2D6CDF),
                            iconBg: isDark
                                ? const Color(0xFF1A2C4F)
                                : const Color(0xFFE5EEFB),
                            label: 'Store',
                            value: order.storeName,
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                          _MetaRow(
                            icon: Icons.person_rounded,
                            iconColor: const Color(0xFF1AB36A),
                            iconBg: isDark
                                ? const Color(0xFF14352A)
                                : const Color(0xFFE7F7EE),
                            label: 'Customer',
                            value: order.customerName,
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                          _MetaRow(
                            icon: Icons.location_on_rounded,
                            iconColor: const Color(0xFF7C3AED),
                            iconBg: isDark
                                ? const Color(0xFF2D2148)
                                : const Color(0xFFEFE9FE),
                            label: 'Drop',
                            value: order.deliveryAddress,
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                          _MetaRow(
                            icon: Icons.route_rounded,
                            iconColor: const Color(0xFFF38B19),
                            iconBg: isDark
                                ? const Color(0xFF3A2613)
                                : const Color(0xFFFFEFDA),
                            label: 'Distance',
                            value:
                                '${order.distanceKm.toStringAsFixed(2)} km',
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                          _MetaRow(
                            icon: Icons.currency_rupee_rounded,
                            iconColor: const Color(0xFF1AB36A),
                            iconBg: isDark
                                ? const Color(0xFF14352A)
                                : const Color(0xFFE7F7EE),
                            label: 'Earnings',
                            value: order.estimatedEarnings > 0
                                ? 'Rs. ${order.estimatedEarnings.toStringAsFixed(0)}'
                                : 'Rs. 0',
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                        ],
                      ),
                    ),
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
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: IgnorePointer(
                child: ColoredBox(color: accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
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
  const _EmptyState({this.storeName});

  final String? storeName;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final msg = storeName != null
        ? 'No pending orders for $storeName'
        : 'No available orders';
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
          Text(msg),
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
