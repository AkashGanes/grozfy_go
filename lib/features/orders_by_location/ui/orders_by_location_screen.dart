import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/services/offline_trip_manager.dart';
import '../../../core/state/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../model/external_delivery.dart';
import '../repository/external_delivery_repository.dart';
import '../../orders/delivery_tracking_screen.dart';
import 'order_location_detail_screen.dart';

class OrdersByLocationScreen extends ConsumerStatefulWidget {
  const OrdersByLocationScreen({super.key});

  @override
  ConsumerState<OrdersByLocationScreen> createState() =>
      _OrdersByLocationScreenState();
}

class _OrdersByLocationScreenState
    extends ConsumerState<OrdersByLocationScreen> {
  late final ExternalDeliveryRepository _repository;
  late final PagingController<int, LocationListItem> _pagingController;
  String? _lastStoreName;
  final Set<String> _submittingOrderIds = <String>{};

  bool _selectionMode = false;
  final Set<String> _selectedOrderIds = <String>{};

  // Orders hidden by the partner's delivery-radius filter, accumulated across
  // loaded pages. Reset on refresh / first page. Drives the "N hidden" hint.
  int _hiddenByRadiusCount = 0;


  // Active filters applied server-side (and to the offline cache). An empty
  // status set / null date range means "no constraint".
  final Set<String> _statusFilter = <String>{};
  DateTimeRange? _dateRange;
  String _customerFilter = '';

  /// External Delivery statuses the driver can filter by on this screen.
  static const List<String> _filterableStatuses = <String>[
    'Pending',
    'Added to Trip',
    'Delivered',
    'Cancelled',
    'Failed',
    'Returned',
    'Return Initiated',
  ];

  bool get _hasActiveFilters =>
      _statusFilter.isNotEmpty ||
      _dateRange != null ||
      _customerFilter.isNotEmpty;

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Builds the Frappe filter clauses for the currently selected status set
  /// and date range. Combined with the store filter inside the repository.
  List<List<dynamic>> _activeFilters() {
    final filters = <List<dynamic>>[];
    if (_statusFilter.isNotEmpty) {
      filters.add(<dynamic>[
        'External Delivery',
        'status',
        'in',
        _statusFilter.toList(),
      ]);
    }
    if (_dateRange != null) {
      filters
        ..add(<dynamic>[
          'External Delivery',
          'creation',
          '>=',
          '${_ymd(_dateRange!.start)} 00:00:00',
        ])
        ..add(<dynamic>[
          'External Delivery',
          'creation',
          '<=',
          '${_ymd(_dateRange!.end)} 23:59:59',
        ]);
    }
    if (_customerFilter.isNotEmpty) {
      filters.add(<dynamic>[
        'External Delivery',
        'customer_name',
        'like',
        '%$_customerFilter%',
      ]);
    }
    return filters;
  }

  @override
  void initState() {
    super.initState();
    _repository = ExternalDeliveryRepository();
    _pagingController = PagingController(firstPageKey: 0)
      ..addPageRequestListener(_fetchPage);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // No forced picker — null selectedStoreName means "All Stores".
      _ensureLocationForRadius();
    });
  }

  /// When the delivery-radius filter is active but the partner's location isn't
  /// known yet, fetch a one-shot GPS fix and refresh so the already-loaded page
  /// re-filters against a real origin. Fails open (leaves the list unfiltered)
  /// when location can't be obtained — e.g. permission denied.
  Future<void> _ensureLocationForRadius() async {
    final controller = ref.read(appControllerProvider);
    if (controller.deliveryRadiusKm == null) return;
    if (controller.currentLatitude != null &&
        controller.currentLongitude != null) {
      return;
    }
    final bool gotLocation = await controller.ensureCurrentLocation();
    if (!mounted || !gotLocation) return;
    // Re-run the filter from the first page now that we have an origin.
    _lastStoreName = null;
    _hiddenByRadiusCount = 0;
    _pagingController.refresh();
  }

  @override
  void dispose() {
    _pagingController.dispose();
    super.dispose();
  }

  Future<void> _fetchPage(int pageKey) async {
    final storeName = ref.read(appControllerProvider).selectedStoreName;

    // TEMP DIAGNOSTIC — confirms the page path runs and which branch.
    debugPrint(
      '[RadiusFilter] _fetchPage pageKey=$pageKey '
      'connected=${ConnectivityService().isConnected} '
      'radius=${ref.read(appControllerProvider).deliveryRadiusKm}',
    );

    // Offline: serve all cached orders for the selected store as a single
    // page. Cache isn't paginated; the dataset is small enough not to be.
    if (!ConnectivityService().isConnected) {
      _serveFromCache(pageKey, storeName);
      return;
    }

    try {
      final orders = await _repository.fetchPage(
        limitStart: pageKey,
        storeName: storeName,
        filters: _activeFilters(),
      );
      ConnectivityService().reportNetworkSuccess();
      // Warm the cache (with the full, unfiltered batch) so the list survives a
      // future offline open and still has every order if the radius changes.
      await OfflineTripManager()
          .cacheOrderSummaries(orders.map(_summaryToMap).toList());

      // The screen may have been popped while these awaits were in flight.
      // Writing to a disposed PagingController throws.
      if (!mounted) return;

      if (pageKey == 0) _hiddenByRadiusCount = 0;
      final visibleOrders = _applyRadiusFilter(orders);

      final items = <LocationListItem>[];
      for (final order in visibleOrders) {
        if (order.storeName != _lastStoreName) {
          items.add(StoreHeader(order.storeName));
          _lastStoreName = order.storeName;
        }
        items.add(OrderRow(order));
      }
      // Paging advances on the raw batch size (not the filtered count) so the
      // radius filter never short-circuits pagination.
      final isLast = orders.length < ExternalDeliveryRepository.pageSize;
      if (isLast) {
        _pagingController.appendLastPage(items);
      } else {
        _pagingController.appendPage(items, pageKey + orders.length);
      }
      // Refresh the parent so the "N hidden by radius" banner reflects the
      // running tally (appending to the paging controller alone won't).
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      if (_isNetworkError(e)) {
        ConnectivityService().reportNetworkFailure();
        _serveFromCache(pageKey, storeName);
        return;
      }
      _pagingController.error = e;
    }
  }

  void _serveFromCache(int pageKey, String? storeName) {
    // TEMP DIAGNOSTIC — confirms the cache path runs.
    debugPrint('[RadiusFilter] _serveFromCache pageKey=$pageKey');
    if (pageKey != 0) {
      _pagingController.appendLastPage(const []);
      return;
    }
    final cached = OfflineTripManager().getCachedOrderSummaries();
    var filtered = storeName == null || storeName.isEmpty
        ? cached
        : cached.where((o) => o.storeName == storeName).toList();
    if (_statusFilter.isNotEmpty) {
      filtered =
          filtered.where((o) => _statusFilter.contains(o.status)).toList();
    }
    if (_dateRange != null) {
      final from = _ymd(_dateRange!.start);
      final to = _ymd(_dateRange!.end);
      filtered = filtered.where((o) {
        if (o.creation.length < 10) return false;
        final day = o.creation.substring(0, 10);
        return day.compareTo(from) >= 0 && day.compareTo(to) <= 0;
      }).toList();
    }
    if (_customerFilter.isNotEmpty) {
      final q = _customerFilter.toLowerCase();
      filtered =
          filtered.where((o) => o.customerName.toLowerCase().contains(q)).toList();
    }
    _hiddenByRadiusCount = 0;
    filtered = _applyRadiusFilter(filtered);
    final items = <LocationListItem>[];
    for (final order in filtered) {
      if (order.storeName != _lastStoreName) {
        items.add(StoreHeader(order.storeName));
        _lastStoreName = order.storeName;
      }
      items.add(OrderRow(order));
    }
    _pagingController.appendLastPage(items);
    if (mounted) setState(() {});
  }

  Map<String, dynamic> _summaryToMap(ExternalDelivery o) => {
        'name': o.name,
        'store_url': o.storeUrl,
        'store_name': o.storeName,
        'customer_name': o.customerName,
        'status': o.status,
        'creation': o.creation,
        'modified': o.modified,
        if (o.latitude != null) 'latitude': o.latitude,
        if (o.longitude != null) 'longitude': o.longitude,
      };

  bool _isNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('network is unreachable') ||
        s.contains('failed host lookup') ||
        s.contains('connection failed') ||
        s.contains('connection refused') ||
        s.contains('connection closed') ||
        s.contains('timed out') ||
        s.contains('clientexception');
  }

  Future<void> _refresh() async {
    _lastStoreName = null;
    _hiddenByRadiusCount = 0;
    _pagingController.refresh();
  }

  /// Splits a freshly loaded batch into the rows within the partner's delivery
  /// radius and the count hidden, updating the running hidden tally. Fails open
  /// (keeps the order) when the order has no coordinates or location is unknown.
  List<ExternalDelivery> _applyRadiusFilter(List<ExternalDelivery> orders) {
    final controller = ref.read(appControllerProvider);
    // TEMP DIAGNOSTIC — logged BEFORE the null-check so we can distinguish
    // "filter not called" from "called but radius is null".
    debugPrint(
      '[RadiusFilter] _applyRadiusFilter CALLED '
      'radius=${controller.deliveryRadiusKm} batchSize=${orders.length} '
      'hiddenCount=$_hiddenByRadiusCount '
      'partnerLat=${controller.currentLatitude} '
      'partnerLng=${controller.currentLongitude}',
    );
    if (controller.deliveryRadiusKm == null) return orders;
    final visible = <ExternalDelivery>[];
    for (final order in orders) {
      final bool keep =
          controller.isWithinDeliveryRadiusAt(order.latitude, order.longitude);
      final double? distance = (order.latitude != null && order.longitude != null)
          ? controller.distanceFromPartnerKm(order.latitude!, order.longitude!)
          : null;
      debugPrint(
        '[RadiusFilter] name=${order.name} lat=${order.latitude} '
        'lng=${order.longitude} distanceKm=$distance '
        'radius=${controller.deliveryRadiusKm} result=${keep ? 'KEEP' : 'HIDE'}',
      );
      if (keep) {
        visible.add(order);
      } else {
        _hiddenByRadiusCount++;
      }
    }
    return visible;
  }

  bool _isEligibleForTrip(ExternalDelivery order) => order.status == 'Pending';

  void _toggleSelection(ExternalDelivery order) {
    if (!_selectionMode) return;
    setState(() {
      if (_selectedOrderIds.contains(order.name)) {
        _selectedOrderIds.remove(order.name);
      } else {
        _selectedOrderIds.add(order.name);
      }
      if (_selectedOrderIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  Future<void> _handleOrderTap(ExternalDelivery order) async {
    if (_submittingOrderIds.contains(order.name)) return;

    if (_selectionMode) {
      _toggleSelection(order);
      return;
    }

    if (_isEligibleForTrip(order)) {
      setState(() => _submittingOrderIds.add(order.name));
      try {
        final app = ref.read(appControllerProvider);
        final error = await app.acceptOrder(order.name);
        if (!mounted) return;

        if (error != null) {
          showInfoSnack(context, error);
          return;
        }

        final active = app.activeOrder;
        if (active == null || !mounted) return;

        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DeliveryTrackingScreen(
              deliveryName: active.orderId,
              customerName: active.customerName,
              storeName: active.storeName,
              contactNumber: active.customerPhone.isNotEmpty
                  ? active.customerPhone
                  : active.contactNumber,
              dropAddress: active.deliveryAddress,
              dropLat: active.latitude,
              dropLng: active.longitude,
            ),
          ),
        );
        if (!mounted) return;
        await _refresh();
      } catch (e) {
        if (!mounted) return;
        showInfoSnack(context, e.toString().replaceFirst('Exception: ', ''));
      } finally {
        if (mounted) {
          setState(() => _submittingOrderIds.remove(order.name));
        }
      }
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OrderLocationDetailScreen(order: order, repository: _repository),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

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

            final currentStore =
                ref.read(appControllerProvider).selectedStoreName;

            return AppBottomSheet(
              title: 'Select Your Location',
              subtitle: 'Orders will be filtered by your selected store.',
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
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          if (i == 0) {
                            final selected = currentStore == null;
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
                                      : AppTheme.nightBlue,
                                ),
                              ),
                              trailing: selected
                                  ? const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppTheme.oceanBlue,
                                    )
                                  : null,
                              onTap: () async {
                                await ref
                                    .read(appControllerProvider)
                                    .setSelectedStore(null);
                                if (ctx.mounted) Navigator.of(ctx).pop();
                                _refresh();
                              },
                            );
                          }

                          final store = stores[i - 1];
                          final selected = currentStore == store;
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
                            onTap: () async {
                              await ref
                                  .read(appControllerProvider)
                                  .setSelectedStore(store);
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              _refresh();
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

  Future<void> _showFilterSheet() async {
    final tempStatuses = Set<String>.from(_statusFilter);
    DateTimeRange? tempRange = _dateRange;
    final customerCtrl = TextEditingController(text: _customerFilter);

    await showAppBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final ColorScheme scheme = Theme.of(ctx).colorScheme;

            Future<void> pickRange() async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: ctx,
                firstDate: DateTime(now.year - 2),
                lastDate: DateTime(now.year + 1, 12, 31),
                initialDateRange: tempRange,
                builder: (context, child) => Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: Theme.of(context).colorScheme.copyWith(
                          primary: AppTheme.oceanBlue,
                        ),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                setModal(() => tempRange = picked);
              }
            }

            return AppBottomSheet(
              title: 'Filter Orders',
              subtitle: 'Filter external deliveries by status and date.',
              leadingIcon: Icons.filter_list_rounded,
              leadingIconColor: AppTheme.oceanBlue,
              scrollable: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  const SectionLabel('Status'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _filterableStatuses.map((status) {
                      final selected = tempStatuses.contains(status);
                      final color = status.statusColor;
                      return GestureDetector(
                        onTap: () => setModal(() {
                          if (selected) {
                            tempStatuses.remove(status);
                          } else {
                            tempStatuses.add(status);
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? color.withValues(alpha: 0.14)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected
                                  ? color
                                  : scheme.onSurface.withValues(alpha: 0.25),
                              width: selected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (selected) ...[
                                Icon(Icons.check_rounded, size: 14, color: color),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                status,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected
                                      ? color
                                      : scheme.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 22),
                  const SectionLabel('Customer'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: customerCtrl,
                    textInputAction: TextInputAction.search,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setModal(() {}),
                    style: TextStyle(fontSize: 14, color: scheme.onSurface),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Filter by customer name…',
                      hintStyle: TextStyle(
                        fontSize: 13.5,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                      prefixIcon: const Icon(
                        Icons.person_outline_rounded,
                        size: 18,
                        color: AppTheme.oceanBlue,
                      ),
                      suffixIcon: customerCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: scheme.onSurface.withValues(alpha: 0.5),
                              ),
                              onPressed: () =>
                                  setModal(() => customerCtrl.clear()),
                            ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: scheme.onSurface.withValues(alpha: 0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.oceanBlue,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const SectionLabel('Order Date'),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: pickRange,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.onSurface.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 18,
                            color: AppTheme.oceanBlue,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              tempRange == null
                                  ? 'Any date'
                                  : '${_ymd(tempRange!.start)}  →  ${_ymd(tempRange!.end)}',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: tempRange == null
                                    ? FontWeight.w500
                                    : FontWeight.w600,
                                color: tempRange == null
                                    ? scheme.onSurface.withValues(alpha: 0.5)
                                    : scheme.onSurface,
                              ),
                            ),
                          ),
                          if (tempRange != null)
                            GestureDetector(
                              onTap: () => setModal(() => tempRange = null),
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: scheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: AppSheetSecondaryButton(
                          label: 'Clear All',
                          icon: Icons.refresh_rounded,
                          onPressed: (tempStatuses.isEmpty &&
                                  tempRange == null &&
                                  customerCtrl.text.trim().isEmpty)
                              ? null
                              : () => setModal(() {
                                  tempStatuses.clear();
                                  tempRange = null;
                                  customerCtrl.clear();
                                }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppSheetPrimaryButton(
                          label: 'Apply',
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            setState(() {
                              _statusFilter
                                ..clear()
                                ..addAll(tempStatuses);
                              _dateRange = tempRange;
                              _customerFilter = customerCtrl.text.trim();
                            });
                            _refresh();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    customerCtrl.dispose();
  }

  Widget _buildFilterAction() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(
            Icons.filter_list_rounded,
            color: AppTheme.nightBlue,
          ),
          tooltip: 'Filter orders',
          onPressed: _showFilterSheet,
        ),
        if (_hasActiveFilters)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: AppTheme.mango,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedStore = ref.watch(appControllerProvider).selectedStoreName;
    final filterCount = _statusFilter.length +
        (_dateRange != null ? 1 : 0) +
        (_customerFilter.isNotEmpty ? 1 : 0);

    return AppShell(
      title: 'Orders by Location',
      subtitle: filterCount > 0
          ? '${selectedStore ?? 'All stores'} · $filterCount filter'
                '${filterCount == 1 ? '' : 's'}'
          : (selectedStore ?? 'Select a location'),
      scrollable: false,
      padding: EdgeInsets.zero,
      actions: [
        _buildFilterAction(),
        IconButton(
          icon: const Icon(Icons.store_rounded, color: AppTheme.nightBlue),
          tooltip: 'Change location',
          onPressed: () => _showStorePicker(),
        ),
      ],
      child: Column(
        children: [
          _buildRadiusHint(),
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.oceanBlue,
              onRefresh: _refresh,
              child: PagedListView<int, LocationListItem>(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          pagingController: _pagingController,
          builderDelegate: PagedChildBuilderDelegate<LocationListItem>(
            itemBuilder: (context, item, index) {
              if (item is StoreHeader) {
                return _StoreHeaderTile(storeName: item.storeName);
              }
              if (item is OrderRow) {
                return _OrderCard(
                  order: item.order,
                  onTap: () => _handleOrderTap(item.order),
                  selected: false,
                  selectionMode: false,
                  onLongPress: () {},
                  busy: false,
                );
              }
              return const SizedBox.shrink();
            },
            firstPageProgressIndicatorBuilder: (_) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: SkeletonLoader(itemCount: 4, spacing: 12),
            ),
            newPageProgressIndicatorBuilder: (_) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppTheme.oceanBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                  )
                      .animate(onPlay: (controller) => controller.repeat())
                      .shimmer(
                        duration: 800.ms,
                        color: AppTheme.oceanBlue.withValues(alpha: 0.3),
                      ),
                ],
              ),
            ),
            noItemsFoundIndicatorBuilder: (_) => const _EmptyState(),
            firstPageErrorIndicatorBuilder: (_) => _ErrorState(
              error: _pagingController.error,
              onRetry: _pagingController.refresh,
            ),
            newPageErrorIndicatorBuilder: (_) => _ErrorState(
              error: _pagingController.error,
              onRetry: _pagingController.retryLastFailedRequest,
            ),
          ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Small banner shown when the partner's delivery-radius filter is hiding
  /// orders, so the list never looks silently truncated. Tapping it opens
  /// Settings to adjust the radius.
  Widget _buildRadiusHint() {
    final radiusKm = ref.watch(appControllerProvider).deliveryRadiusKm;
    if (radiusKm == null || _hiddenByRadiusCount <= 0) {
      return const SizedBox.shrink();
    }
    final String radiusLabel = radiusKm == radiusKm.roundToDouble()
        ? radiusKm.toStringAsFixed(0)
        : radiusKm.toStringAsFixed(1);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
}

// ---------------------------------------------------------------------------
// Store section header
// ---------------------------------------------------------------------------

class _StoreHeaderTile extends StatelessWidget {
  const _StoreHeaderTile({required this.storeName});
  final String storeName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: SectionLabel(storeName),
    );
  }
}

// ---------------------------------------------------------------------------
// Order card
// ---------------------------------------------------------------------------

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onTap,
    required this.selected,
    required this.selectionMode,
    required this.onLongPress,
    this.busy = false,
  });
  final ExternalDelivery order;
  final VoidCallback onTap;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onLongPress;
  final bool busy;

  String _formatDate(String raw) {
    if (raw.length < 10) return raw;
    final parts = raw.substring(0, 10).split('-');
    if (parts.length != 3) return raw.substring(0, 10);
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final statusColor = order.status.statusColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: busy ? 0.7 : 1,
        child: GestureDetector(
          onTap: busy ? null : onTap,
          onLongPress: busy ? null : onLongPress,
          child: FrostCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (selectionMode) ...[
                  Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.oceanBlue : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected
                            ? AppTheme.oceanBlue
                            : scheme.onSurface.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ] else ...[
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(right: 12, top: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.4),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.3),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ],
                // Order info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 13,
                            color: scheme.onSurface.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              order.customerName,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurface.withValues(alpha: 0.6),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.schedule,
                            size: 13,
                            color: scheme.onSurface.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(order.modified),
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                      if (order.storeName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.store_outlined,
                              size: 12,
                              color: Colors.black38,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                order.storeName,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black38,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    order.status,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: FrostCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 52,
              color: AppTheme.oceanBlue.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'No orders found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pull down to refresh',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: FrostCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppTheme.mango.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 12),
            Text(
              error?.toString() ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
