import 'dart:async';
import 'dart:math';

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
import '../orders_by_location/model/external_delivery_detail.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';

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
  late final PagingController<int, DeliveryOrder> _pagingController;
  final TextEditingController _searchController = TextEditingController();
  AppController? _app;

  // Search state
  String _searchQuery = '';
  List<ExternalDeliveryDetail> _searchResults = [];
  bool _searchLoading = false;
  String? _searchError;
  Timer? _debounce;
  bool _showSearchBar = false;

  // Store filter state
  String? _selectedStore;

  // Track which search-result card is being opened
  String? _openingOrderId;

  // Batch selection state
  static const int _batchLimit = 3;
  bool _selectionMode = false;
  final Set<String> _selectedOrderIds = {};
  final List<DeliveryOrder> _selectedOrders = [];
  bool _creatingBatchTrip = false;

  // Delivery-radius filter state. The business policy (enabled/default/max)
  // lives on the Driver doc and the partner's selection in AppController; this
  // screen just applies it. _hiddenByRadiusCount tallies orders hidden across
  // loaded pages for the banner; _lastRadiusKm detects Settings-slider changes.
  int _hiddenByRadiusCount = 0;
  double? _lastRadiusKm;
  bool _radiusInitDone = false;

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
    _syncDeliveryRadius();
  }

  /// Reacts to delivery-radius changes (the Settings slider). On first run it
  /// seeds the partner's GPS location for the filter; on later changes it
  /// refreshes the list so the radius re-applies. AppScope is an
  /// InheritedNotifier, so this fires whenever AppController notifies.
  void _syncDeliveryRadius() {
    final app = _app;
    if (app == null) return;
    final double? radius = app.deliveryRadiusKm;
    if (!_radiusInitDone) {
      _radiusInitDone = true;
      _lastRadiusKm = radius;
      _ensureLocationForRadius();
      return;
    }
    if (radius != _lastRadiusKm) {
      _lastRadiusKm = radius;
      _hiddenByRadiusCount = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pagingController.refresh();
      });
    }
  }

  /// When the delivery-radius filter is active but the partner's location isn't
  /// known yet, fetch a one-shot GPS fix and refresh so the loaded page
  /// re-filters against a real origin. Fails open (leaves the list unfiltered)
  /// when location can't be obtained — e.g. permission denied.
  Future<void> _ensureLocationForRadius() async {
    final app = _app;
    if (app == null || app.deliveryRadiusKm == null) return;
    if (app.currentLatitude != null && app.currentLongitude != null) return;
    final bool ok = await app.ensureCurrentLocation();
    if (!mounted || !ok) return;
    _hiddenByRadiusCount = 0;
    _pagingController.refresh();
  }

  /// Keeps only the orders within the partner's delivery radius, tallying the
  /// hidden count for the banner. Fails open: orders without coordinates
  /// (lat/lng both 0) — or when the partner location/radius is unknown — are
  /// kept, so a data/GPS gap never empties the work list.
  List<DeliveryOrder> _applyRadiusFilter(
    AppController app,
    List<DeliveryOrder> orders,
  ) {
    if (app.deliveryRadiusKm == null) return orders;
    final visible = <DeliveryOrder>[];
    for (final order in orders) {
      final bool hasCoords = order.latitude != 0 || order.longitude != 0;
      final bool keep = !hasCoords ||
          app.isWithinDeliveryRadiusAt(order.latitude, order.longitude);
      if (keep) {
        visible.add(order);
      } else {
        _hiddenByRadiusCount++;
      }
    }
    return visible;
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

    try {
      final fetched = await _fetchOrdersEnriched(app, pageKey);
      if (!mounted) return;

      if (pageKey == 0) _hiddenByRadiusCount = 0;
      // Filter by delivery radius for display; pagination still advances on the
      // RAW batch size so the filter never short-circuits paging.
      final orders = _applyRadiusFilter(app, fetched);

      final isLast = fetched.length < _pageSize;
      if (isLast) {
        _pagingController.appendLastPage(orders);
      } else {
        _pagingController.appendPage(orders, pageKey + fetched.length);
      }
      // Update the "N hidden" banner with the running tally.
      if (mounted) setState(() {});
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
        orderBy: 'modified desc',
        filters: <List<dynamic>>[
          <dynamic>['External Delivery', 'status', '=', 'Pending'],
          ...storeFilter,
        ],
      );
      return details.map((d) => app.buildDeliveryOrderFromDetail(d)).toList();
    } catch (e) {
      debugPrint('[OrderListing] reportview failed, using summary fallback: $e');
    }

    // Fallback: single fetchPage call — no per-item detail fetches.
    final summaries = await _repository.fetchPage(
      limitStart: pageKey,
      limitPageLength: _pageSize,
      storeName: _selectedStore,
      orderBy: 'modified desc',
      filters: <List<dynamic>>[
        <dynamic>['External Delivery', 'status', '=', 'Pending'],
      ],
    );
    return summaries
        .map((s) => app.buildDeliveryOrderFromDetail(_summaryToDetail(s)))
        .toList();
  }

  static ExternalDeliveryDetail _summaryToDetail(ExternalDelivery s) {
    return ExternalDeliveryDetail(
      name: s.name,
      storeName: s.storeName,
      storeUrl: s.storeUrl,
      customerName: s.customerName,
      status: s.status,
      deliveryAddress: s.deliveryAddress,
      creation: s.creation,
      modified: s.modified,
    );
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
      List<ExternalDeliveryDetail> results;
      try {
        results = await _repository.fetchPageEnriched(
          limitStart: 0,
          limitPageLength: 100,
          orderBy: 'modified desc',
          filters: <List<dynamic>>[
            <dynamic>['External Delivery', 'status', '=', 'Pending'],
            if (_selectedStore != null)
              <dynamic>[
                'External Delivery',
                'store_name',
                '=',
                _selectedStore,
              ],
          ],
          orFilters: <List<dynamic>>[
            <dynamic>['External Delivery', 'name', 'like', '%$query%'],
            <dynamic>['External Delivery', 'store_name', 'like', '%$query%'],
            <dynamic>['External Delivery', 'customer_name', 'like', '%$query%'],
          ],
        );
      } catch (_) {
        // Fallback: single fetchPage call — no per-result detail fetches.
        final summaries = await _repository.fetchPage(
          limitStart: 0,
          limitPageLength: 100,
          orderBy: 'modified desc',
          filters: <List<dynamic>>[
            <dynamic>['External Delivery', 'status', '=', 'Pending'],
            if (_selectedStore != null)
              <dynamic>[
                'External Delivery',
                'store_name',
                '=',
                _selectedStore,
              ],
          ],
          orFilters: <List<dynamic>>[
            <dynamic>['External Delivery', 'name', 'like', '%$query%'],
            <dynamic>['External Delivery', 'store_name', 'like', '%$query%'],
            <dynamic>['External Delivery', 'customer_name', 'like', '%$query%'],
          ],
        );
        results = summaries.map(_summaryToDetail).toList();
      }
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

  void _openSearchResult(ExternalDeliveryDetail detail) {
    final app = _app;
    if (app == null) return;
    final order = app.buildDeliveryOrderFromDetail(detail);
    Navigator.of(context).pushNamed(AppRoutes.orderDetails, arguments: order);
  }

  // ── Batch selection ────────────────────────────────────────────────────────

  void _enterSelectionMode(DeliveryOrder order) {
    setState(() {
      _selectionMode = true;
      _selectedOrderIds.add(order.orderId);
      _selectedOrders.add(order);
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) { if (mounted) _pagingController.notifyListeners(); },
    );
  }

  void _toggleSelection(DeliveryOrder order) {
    if (!_selectedOrderIds.contains(order.orderId) &&
        _selectedOrderIds.length >= _batchLimit) {
      AppToast.show(
        context,
        'Maximum $_batchLimit orders can be added to one trip',
      );
      return;
    }
    setState(() {
      if (_selectedOrderIds.contains(order.orderId)) {
        _selectedOrderIds.remove(order.orderId);
        _selectedOrders.removeWhere((o) => o.orderId == order.orderId);
        if (_selectedOrderIds.isEmpty) _selectionMode = false;
      } else {
        _selectedOrderIds.add(order.orderId);
        _selectedOrders.add(order);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) { if (mounted) _pagingController.notifyListeners(); },
    );
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedOrderIds.clear();
      _selectedOrders.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) { if (mounted) _pagingController.notifyListeners(); },
    );
  }

  Future<void> _createBatchTrip() async {
    if (_selectedOrderIds.isEmpty || _creatingBatchTrip) return;

    if (_checkDistanceWarning()) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF38B19)),
              SizedBox(width: 8),
              Text(
                'Large Distance',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: const Text(
            'Some selected orders are more than 3 km apart. Create the trip anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F5FE8),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Create Trip'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    setState(() => _creatingBatchTrip = true);
    try {
      final orders = _selectedOrders
          .map(
            (o) => ExternalDelivery(
              name: o.orderId,
              storeUrl: '',
              storeName: '',
              customerName: '',
              status: '',
              creation: '',
              modified: '',
            ),
          )
          .toList();

      final tripName = await _repository.createTripForOrders(orders);
      if (!mounted) return;

      _exitSelectionMode();
      _pagingController.refresh();
      AppToast.show(context, 'Trip $tripName created (${orders.length} orders)');
      Navigator.of(context).pushNamed(AppRoutes.externalDeliveryTripList);
    } catch (e) {
      if (mounted) AppToast.show(context, 'Failed to create trip: $e');
    } finally {
      if (mounted) setState(() => _creatingBatchTrip = false);
    }
  }

  bool _checkDistanceWarning() {
    if (_selectedOrders.length < 2) return false;
    const double maxKm = 3.0;
    for (int i = 0; i < _selectedOrders.length; i++) {
      for (int j = i + 1; j < _selectedOrders.length; j++) {
        final a = _selectedOrders[i];
        final b = _selectedOrders[j];
        if (a.latitude != 0 && b.latitude != 0) {
          if (_haversineKm(
                a.latitude,
                a.longitude,
                b.latitude,
                b.longitude,
              ) >
              maxKm) {
            return true;
          }
        }
      }
    }
    return false;
  }

  double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double r = 6371.0;
    final double dLat = (lat2 - lat1) * pi / 180;
    final double dLon = (lon2 - lon1) * pi / 180;
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  Widget _buildSelectionBar() {
    final double bottomPad = MediaQuery.of(context).padding.bottom;
    // Positioned(left:0, right:0) above gives this tight finite width —
    // no SizedBox wrapper needed.
    return Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancel'),
              onPressed: _exitSelectionMode,
            ),
            const Spacer(),
            Text(
              '${_selectedOrderIds.length} selected',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(width: 12),
            // Plain Material+InkWell avoids ElevatedButton's theme fixedSize
            // (app theme sets fixedSize: Size(infinity, 52) which crashes
            // in any unconstrained-width context including Positioned children).
            Material(
              color: _creatingBatchTrip
                  ? const Color(0xFF1F5FE8).withValues(alpha: 0.6)
                  : const Color(0xFF1F5FE8),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: _creatingBatchTrip ? null : _createBatchTrip,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_creatingBatchTrip)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else
                        const Icon(
                          Icons.route_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      const SizedBox(width: 6),
                      const Text(
                        'Create Trip',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool searching = _searchQuery.length >= 2;

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _exitSelectionMode();
      },
      // Outer Stack so the selection bar can be Positioned with tight
      // horizontal constraints from the route — bypassing AppShell's
      // internal Stack which provides unconstrained width to its children.
      child: Stack(
        children: [
      AppShell(
        title: _app?.t('available_orders') ?? 'New Orders',
        subtitle: _selectionMode
            ? '${_selectedOrderIds.length} order${_selectedOrderIds.length == 1 ? '' : 's'} selected'
            : (_selectedStore ?? 'All Stores'),
        scrollable: false,
        actions: [
          if (!_selectionMode) ...[
            IconButton(
              icon: Icon(
                _showSearchBar ? Icons.search_off_rounded : Icons.search_rounded,
                color: AppTheme.nightBlue,
              ),
              tooltip: 'Search orders',
              onPressed: () {
                if (_showSearchBar) _clearSearch();
                setState(() => _showSearchBar = !_showSearchBar);
              },
            ),
            IconButton(
              icon: const Icon(Icons.store_rounded, color: AppTheme.nightBlue),
              tooltip: 'Filter by store',
              onPressed: _showStorePicker,
            ),
          ],
        ],
        child: Column(
          children: [
          // Search bar — collapsed by default, revealed via the header icon so
          // it doesn't compete with the order list for a first-time driver's
          // attention.
          if (_showSearchBar)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: KycSearchInput(
              controller: _searchController,
              hint: 'Search by Order ID, Store or Customer…',
              autofocus: true,
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

          // Delivery-radius "N hidden" banner (only in browse mode).
          if (!searching) _buildRadiusHint(),

          // List area
          Expanded(
            child: searching
                ? _buildSearchView()
                : RefreshIndicator(
                    onRefresh: () async {
                      _pagingController.refresh();
                    },
                    color: Colors.orange,
                    child: _buildPagedList(),
                  ),
          ),
          ],
        ),
      ),
      // Selection bar as Positioned — gets tight horizontal constraints
      // from the route-level Stack, not AppShell's unconstrained Stack.
      if (_selectionMode)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildSelectionBar(),
        ),
        ],
      ),
    );
  }

  /// Banner shown when the delivery-radius filter is hiding orders, so the list
  /// never looks silently truncated.
  Widget _buildRadiusHint() {
    final double? radiusKm = _app?.deliveryRadiusKm;
    if (radiusKm == null || _hiddenByRadiusCount <= 0) {
      return const SizedBox.shrink();
    }
    final String radiusLabel = radiusKm == radiusKm.roundToDouble()
        ? radiusKm.toStringAsFixed(0)
        : radiusKm.toStringAsFixed(1);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.oceanBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.oceanBlue.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.my_location_rounded,
              size: 18, color: AppTheme.oceanBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_hiddenByRadiusCount order'
              '${_hiddenByRadiusCount == 1 ? '' : 's'} hidden by your '
              '$radiusLabel km radius',
              style: const TextStyle(fontSize: 13, color: AppTheme.nightBlue),
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
      padding: EdgeInsets.fromLTRB(
        0, 4, 0,
        _selectionMode ? MediaQuery.of(context).padding.bottom + 80 : 20,
      ),
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
        noItemsFoundIndicatorBuilder: (_) =>
            _EmptyState(storeName: _selectedStore),
        itemBuilder: (context, order, index) {
          final bool isSelected = _selectedOrderIds.contains(order.orderId);
          return _FullOrderCard(
            order: order,
            isSelected: isSelected,
            inSelectionMode: _selectionMode,
            onLongPress: _selectionMode ? null : () => _enterSelectionMode(order),
            onTap: _selectionMode
                ? () => _toggleSelection(order)
                : () => Navigator.of(context).pushNamed(
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
      padding: EdgeInsets.fromLTRB(
        0, 4, 0,
        _selectionMode ? MediaQuery.of(context).padding.bottom + 80 : 20,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final detail = _searchResults[index];
        return _SearchResultCard(
          detail: detail,
          query: _searchQuery,
          onTap: () => _openSearchResult(detail),
        );
      },
    );
  }
}

// ── Full detail card ──────────────────────────────────────────────────────────

class _FullOrderCard extends StatelessWidget {
  const _FullOrderCard({
    required this.order,
    required this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.inSelectionMode = false,
  });

  final DeliveryOrder order;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool inSelectionMode;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark ? const Color(0xFF1B1E2A) : Colors.white;
    final Color cardBorder = isSelected
        ? const Color(0xFF1AB36A)
        : (isDark ? const Color(0xFF2A2F3D) : const Color(0xFFE4E7EC));
    final Color textPrimary =
        isDark ? const Color(0xFFF2F4F7) : const Color(0xFF101828);
    final Color textSecondary =
        isDark ? const Color(0xFFA4ABB8) : const Color(0xFF667085);
    const Color accent = Color(0xFF1F5FE8);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        // Long-press lives on the outer GestureDetector so the scroll view
        // can still win the gesture arena independently of the tap InkWell.
        onLongPress: onLongPress,
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
                  color: isSelected
                      ? const Color(0xFF1AB36A).withValues(alpha: 0.06)
                      : cardBg,
                  border: Border.all(
                    color: cardBorder,
                    width: isSelected ? 2 : 1,
                  ),
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
                              if (inSelectionMode)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF1AB36A)
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF1AB36A)
                                          : const Color(0xFF9AA3AF),
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: isSelected
                                      ? const Icon(
                                          Icons.check_rounded,
                                          size: 16,
                                          color: Colors.white,
                                        )
                                      : null,
                                )
                              else
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
                    if (!inSelectionMode)
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
    required this.detail,
    required this.query,
    required this.onTap,
  });

  final ExternalDeliveryDetail detail;
  final String query;
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
                        text: detail.name,
                        query: query,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      _Highlight(
                        text: detail.storeName,
                        query: query,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 2),
                      _Highlight(
                        text: detail.customerName,
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
