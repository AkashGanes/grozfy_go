import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/models/app_models.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/context_colors.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/offline_state_view.dart';
import '../kyc/widgets/kyc_form_widgets.dart';
import '../delivery_radius/repository/delivery_radius_repository.dart';
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
  static const Duration _searchDebounce = Duration(milliseconds: 450);
  // Single-page size for the rollout fallback (used only when the radius-aware
  // `list_available_deliveries` method isn't deployed yet).
  static const int _fallbackPageLength = 200;

  late final ExternalDeliveryRepository _repository;
  late final DeliveryRadiusRepository _radiusRepository;
  late final PagingController<int, DeliveryOrder> _pagingController;

  // Client-side delivery-radius filter (stopgap until the backend ships
  // `list_available_deliveries`). Resolved once per list load; null means
  // "don't filter" (feature off, bad bounds, or radius unavailable).
  double? _radiusKm;
  bool _radiusResolved = false;
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

  // Tracks the driver's availability so we can reload the list when it flips.
  // Offline drivers must not see the available/Pending order pool.
  bool? _lastOnline;

  @override
  void initState() {
    super.initState();
    _repository = ExternalDeliveryRepository();
    _radiusRepository = DeliveryRadiusRepository();
    _pagingController = PagingController<int, DeliveryOrder>(firstPageKey: 0)
      ..addPageRequestListener(_fetchPage);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = AppScope.of(context);
    _syncOnlineState();
  }

  /// Reloads the list when the driver's availability flips. AppScope is an
  /// InheritedNotifier, so this fires whenever AppController notifies. Going
  /// Offline empties the list (no available orders reach an Offline driver);
  /// going back Online refills it.
  void _syncOnlineState() {
    final bool online = _app?.isOnline ?? false;
    if (_lastOnline != null && online != _lastOnline) {
      _hiddenByRadiusCount = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pagingController.refresh();
      });
    }
    _lastOnline = online;
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
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: context.scheme.primary,
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
                                    ? context.scheme.primary
                                    : ctx.iconMuted,
                              ),
                              title: Text(
                                'All Stores',
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected
                                      ? context.scheme.primary
                                      : scheme.onSurface,
                                ),
                              ),
                              trailing: selected
                                  ? Icon(
                                      Icons.check_circle_rounded,
                                      color: context.scheme.primary,
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
                                  ? context.scheme.primary
                                  : scheme.onSurface.withValues(alpha: 0.4),
                            ),
                            title: Text(
                              store,
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? context.scheme.primary
                                    : scheme.onSurface,
                              ),
                            ),
                            trailing: selected
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color: context.scheme.primary,
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

    // Re-resolve the radius at the start of each new list, so a radius change
    // in Settings takes effect on pull-to-refresh.
    if (pageKey == 0) {
      _radiusResolved = false;
    }

    // Offline drivers must not receive new/available orders. Skip the fetch
    // entirely and show an empty list; the paged list's noItemsFound builder
    // renders an explicit "You are Offline" notice.
    if (!app.isOnline) {
      if (!mounted) return;
      _pagingController.appendLastPage(<DeliveryOrder>[]);
      return;
    }

    // The radius-aware feed returns the full pool in one call, so there is only
    // ever a single page. Any request beyond the first is empty.
    if (pageKey != 0) {
      _pagingController.appendLastPage(<DeliveryOrder>[]);
      return;
    }

    try {
      final orders = await _fetchOrdersEnriched(app, pageKey);
      if (!mounted) return;

      _pagingController.appendLastPage(orders);
    } catch (e, st) {
      debugPrint('[OrderListing] _fetchPage error: $e');
      debugPrint('[OrderListing] stacktrace: $st');
      if (!mounted) return;
      _pagingController.error = e;
    }
  }

  /// Loads the available (Pending) order pool from the radius-aware
  /// `list_available_deliveries` feed — the server filters by the driver's
  /// delivery radius and returns the full set in one call, each row carrying a
  /// server-computed `distance_km`. Pagination is a no-op here (the caller
  /// requests only page 0); [pageKey] is retained for signature compatibility.
  ///
  /// Rollout safety: if the backend method isn't deployed yet, we fall back to
  /// the generic Pending list so the screen keeps working (un-radius-filtered)
  /// until the backend ships. Only a "method unavailable" error triggers the
  /// fallback — genuine network/auth errors are rethrown so the list surfaces
  /// its normal error/retry state.
  Future<List<DeliveryOrder>> _fetchOrdersEnriched(
    AppController app,
    int pageKey,
  ) async {
    try {
      final summaries = await _repository.fetchAvailableDeliveries(
        storeName: _selectedStore,
        filters: <List<dynamic>>[
          <dynamic>['External Delivery', 'status', '=', 'Pending'],
        ],
      );
      return summaries
          .map((s) => app.buildDeliveryOrderFromDetail(_summaryToDetail(s)))
          .toList();
    } catch (e) {
      if (!_isMethodUnavailable(e)) rethrow;
      debugPrint(
        '[OrderListing] list_available_deliveries unavailable, falling back '
        'to the generic Pending list: $e',
      );
      return _fetchOrdersGenericFallback(app);
    }
  }

  /// True when [e] indicates the backend method simply isn't deployed (Frappe's
  /// "no attribute" / "Failed to get method" or a 404), as opposed to a real
  /// network/permission failure we should not paper over.
  static bool _isMethodUnavailable(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('has no attribute') ||
        s.contains('failed to get method') ||
        s.contains('404');
  }

  /// Fallback path used only while `list_available_deliveries` is undeployed:
  /// the pre-existing generic fetch (reportview first, summary list second),
  /// pulled as a single large page to preserve the single-call model. The
  /// server can't radius-filter here, so we apply the driver's delivery radius
  /// client-side ([_filterByRadius]) to reproduce what the backend will do.
  Future<List<DeliveryOrder>> _fetchOrdersGenericFallback(
    AppController app,
  ) async {
    final storeFilter = _selectedStore != null && _selectedStore!.isNotEmpty
        ? [<dynamic>['External Delivery', 'store_name', '=', _selectedStore]]
        : <List<dynamic>>[];

    try {
      final details = await _repository.fetchPageEnriched(
        limitStart: 0,
        limitPageLength: _fallbackPageLength,
        orderBy: 'modified desc',
        filters: <List<dynamic>>[
          <dynamic>['External Delivery', 'status', '=', 'Pending'],
          ...storeFilter,
        ],
      );
      return _filterByRadius(
        details.map((d) => app.buildDeliveryOrderFromDetail(d)).toList(),
      );
    } catch (e) {
      debugPrint('[OrderListing] reportview fallback failed, using summary: $e');
    }

    final summaries = await _repository.fetchPage(
      limitStart: 0,
      limitPageLength: _fallbackPageLength,
      storeName: _selectedStore,
      orderBy: 'modified desc',
      filters: <List<dynamic>>[
        <dynamic>['External Delivery', 'status', '=', 'Pending'],
      ],
    );
    return _filterByRadius(
      summaries
          .map((s) => app.buildDeliveryOrderFromDetail(_summaryToDetail(s)))
          .toList(),
    );
  }

  /// Resolves the driver's effective delivery radius (km) once per list load.
  /// Returns null — meaning "don't filter" — when the feature is off, bounds
  /// are invalid, or the settings call fails (better to show everything than to
  /// hide the whole pool on a transient error).
  Future<double?> _effectiveRadiusKm() async {
    if (_radiusResolved) return _radiusKm;
    _radiusResolved = true;
    try {
      final s = await _radiusRepository.getSettings();
      _radiusKm = (s.enabled && s.hasValidBounds) ? s.effectiveRadiusKm : null;
    } catch (_) {
      _radiusKm = null;
    }
    return _radiusKm;
  }

  /// Keeps only orders within the driver's delivery radius. Orders with an
  /// unknown distance (0 — missing coordinates or no driver location yet) are
  /// kept, so a missing GPS fix never blanks the list.
  Future<List<DeliveryOrder>> _filterByRadius(
    List<DeliveryOrder> orders,
  ) async {
    final radius = await _effectiveRadiusKm();
    if (radius == null || radius <= 0) return orders;
    final filtered = orders
        .where((o) => o.distanceKm <= 0 || o.distanceKm <= radius)
        .toList();
    debugPrint(
      '[OrderListing] radius filter: ${orders.length} → ${filtered.length} '
      'within ${radius}km',
    );
    return filtered;
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
      latitude: s.latitude,
      longitude: s.longitude,
      distanceKm: s.distanceKm,
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
    // Search returns available (Pending) orders — that's NEW work, so an
    // Offline driver must not be able to surface it. Mirror the _fetchPage
    // gate: return no results while Offline.
    if (!(_app?.isOnline ?? false)) {
      setState(() {
        _searchLoading = false;
        _searchError = null;
        _searchResults = [];
      });
      return;
    }
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

    // Offline drivers can't take on work. This path creates a trip directly
    // via the repository, bypassing AppController.acceptOrder, so it needs its
    // own guard.
    if (!(_app?.isOnline ?? false)) {
      AppToast.show(context, 'You are Offline. Go Online to accept orders.');
      return;
    }

    if (_checkDistanceWarning()) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: ctx.warning),
              const SizedBox(width: 8),
              const Text(
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
                backgroundColor: context.scheme.primary,
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
              color: context.shadowColor,
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
                  ? context.scheme.primary.withValues(alpha: 0.6)
                  : context.scheme.primary,
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
                color: context.iconPrimary,
              ),
              tooltip: 'Search orders',
              onPressed: () {
                if (_showSearchBar) _clearSearch();
                setState(() => _showSearchBar = !_showSearchBar);
              },
            ),
            IconButton(
              icon: Icon(Icons.store_rounded, color: context.iconPrimary),
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
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.scheme.primary,
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
                      color: context.danger,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _searchError!,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.danger,
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
                        color: context.scheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: context.scheme.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        '${_searchResults.length} result${_searchResults.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.scheme.primary,
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
        noItemsFoundIndicatorBuilder: (_) => (_app?.isOnline ?? true)
            ? _EmptyState(storeName: _selectedStore)
            : OfflineStateView(
                message: 'Go Online to see available orders.',
                onGoOnline: _app == null ? null : () => _app!.setOnline(true),
              ),
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
    final Color cardBg = context.cardColor;
    final Color cardBorder =
        isSelected ? context.success : context.borderSubtle;
    final Color textPrimary = context.textPrimary;
    final Color textSecondary = context.textSecondary;
    final Color accent = context.scheme.primary;

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
                      ? context.success.withValues(alpha: 0.06)
                      : cardBg,
                  border: Border.all(
                    color: cardBorder,
                    width: isSelected ? 2 : 1,
                  ),
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
                                        ? context.success
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: isSelected
                                          ? context.success
                                          : context.borderStrong,
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
                                  color: context.warningContainer,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  'UNASSIGNED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: context.warning,
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
                            iconBg: context.infoContainer,
                            label: 'Store',
                            value: order.storeName,
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                          _MetaRow(
                            icon: Icons.person_rounded,
                            iconColor: const Color(0xFF1AB36A),
                            iconBg: context.successContainer,
                            label: 'Customer',
                            value: order.customerName,
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                          _MetaRow(
                            icon: Icons.location_on_rounded,
                            iconColor: const Color(0xFF7C3AED),
                            iconBg: context.isDark
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
                            iconBg: context.isDark
                                ? const Color(0xFF3A2613)
                                : const Color(0xFFFFEFDA),
                            label: 'Distance',
                            value: order.distanceKm > 0
                                ? '${order.distanceKm.toStringAsFixed(2)} km'
                                : '—',
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                          _MetaRow(
                            icon: Icons.currency_rupee_rounded,
                            iconColor: const Color(0xFF1AB36A),
                            iconBg: context.successContainer,
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
                    color: context.scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.shopping_bag_rounded,
                    color: context.scheme.primary,
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
              color: context.scheme.primary,
              fontWeight: FontWeight.bold,
              backgroundColor: context.scheme.primary.withValues(alpha: 0.1),
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
