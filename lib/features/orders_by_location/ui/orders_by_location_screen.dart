import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../core/navigation/app_routes.dart';
import '../../../core/state/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../model/external_delivery.dart';
import '../model/external_delivery_detail.dart';
import '../repository/external_delivery_repository.dart';
import '../../orders/delivery_tracking_screen.dart';
import 'order_location_detail_screen.dart';

const double _maxDistanceWarningKm = 3.0;

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
  bool _creatingTrip = false;
  final List<ExternalDeliveryDetail> _orderDetailsCache = [];

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _repository = ExternalDeliveryRepository();
    _pagingController = PagingController(firstPageKey: 0)
      ..addPageRequestListener(_fetchPage);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // No forced picker — null selectedStoreName means "All Stores".
    });
  }

  @override
  void dispose() {
    _pagingController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchPage(int pageKey) async {
    try {
      final storeName = ref.read(appControllerProvider).selectedStoreName;
      final orders = await _repository.fetchPage(
        limitStart: pageKey,
        storeName: storeName,
      );
      final items = <LocationListItem>[];
      for (final order in orders) {
        if (order.storeName != _lastStoreName) {
          items.add(StoreHeader(order.storeName));
          _lastStoreName = order.storeName;
        }
        items.add(OrderRow(order));
      }
      final isLast = orders.length < ExternalDeliveryRepository.pageSize;
      if (isLast) {
        _pagingController.appendLastPage(items);
      } else {
        _pagingController.appendPage(items, pageKey + orders.length);
      }
    } catch (e) {
      _pagingController.error = e;
    }
  }

  Future<void> _refresh() async {
    _lastStoreName = null;
    _pagingController.refresh();
  }

  bool _isEligibleForTrip(ExternalDelivery order) => order.status == 'Pending';

  void _enterSelectionMode() {
    setState(() {
      _selectionMode = true;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedOrderIds.clear();
    });
  }

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

  double _calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadiusKm = 6371.0;
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180.0;

  Future<List<ExternalDeliveryDetail>> _fetchOrderDetails(
    List<ExternalDelivery> orders,
  ) async {
    final details = <ExternalDeliveryDetail>[];
    for (final order in orders) {
      final cached = _orderDetailsCache.firstWhere(
        (d) => d.name == order.name,
        orElse: () => ExternalDeliveryDetail(
          name: '',
          storeName: '',
          storeUrl: '',
          customerName: '',
          status: '',
        ),
      );
      if (cached.name.isNotEmpty) {
        details.add(cached);
      } else {
        try {
          final detail = await _repository.fetchDetail(order.name);
          details.add(detail);
          _orderDetailsCache.add(detail);
        } catch (_) {
          // Skip orders we can't get details for
        }
      }
    }
    return details;
  }

  (bool hasWarning, String message) _checkDistanceWarning(
    List<ExternalDeliveryDetail> details,
  ) {
    for (int i = 0; i < details.length; i++) {
      for (int j = i + 1; j < details.length; j++) {
        final d1 = details[i];
        final d2 = details[j];
        if (d1.latitude != null &&
            d1.longitude != null &&
            d2.latitude != null &&
            d2.longitude != null) {
          final distance = _calculateDistanceKm(
            d1.latitude!,
            d1.longitude!,
            d2.latitude!,
            d2.longitude!,
          );
          if (distance > _maxDistanceWarningKm) {
            return (
              true,
              '${d1.customerName} and ${d2.customerName} are ${distance.toStringAsFixed(1)} km apart. Consider creating separate trips.',
            );
          }
        }
      }
    }
    return (false, '');
  }

  Future<void> _showDistanceWarningDialog(
    List<ExternalDelivery> selectedOrders,
  ) async {
    final details = await _fetchOrderDetails(selectedOrders);
    if (!mounted) return;

    final (hasWarning, message) = _checkDistanceWarning(details);
    if (!hasWarning) {
      await _createBatchTrip(selectedOrders);
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.mango, size: 28),
            const SizedBox(width: 10),
            const Text('Distance Warning'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.oceanBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Create Anyway'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      await _createBatchTrip(selectedOrders);
    }
  }

  Future<void> _handleCreateTrip() async {
    if (_selectedOrderIds.isEmpty) return;

    final allItems = _pagingController.itemList ?? [];
    final selectedOrders = allItems
        .whereType<OrderRow>()
        .where((r) => _selectedOrderIds.contains(r.order.name))
        .map((r) => r.order)
        .toList();

    final stale = selectedOrders
        .where((o) => !_isEligibleForTrip(o))
        .map((o) => o.name)
        .toList();
    if (stale.isNotEmpty) {
      showInfoSnack(
        context,
        '${stale.length} order${stale.length == 1 ? ' is' : 's are'} no longer available. Refreshing list.',
      );
      _exitSelectionMode();
      await _refresh();
      return;
    }

    await _showDistanceWarningDialog(selectedOrders);
  }

  Future<void> _createBatchTrip(List<ExternalDelivery> orders) async {
    if (_creatingTrip) return;
    setState(() => _creatingTrip = true);

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final tripName = await _repository.createAndSubmitTripForOrders(orders);
      if (!mounted) return;

      _exitSelectionMode();
      await _refresh();

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Trip created with ${orders.length} orders'),
          action: SnackBarAction(
            label: 'View Trip',
            onPressed: () {
              navigator.pushNamed(
                AppRoutes.externalDeliveryTripDetails,
                arguments: tripName,
              );
            },
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showInfoSnack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _creatingTrip = false);
      }
    }
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
        // acceptOrder: updates Frappe status → 'Added to Trip', creates the
        // External Delivery Trip document, and sets app.activeOrder so the
        // full tracking + cancel/confirm/earnings flow works correctly.
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

  void _handleOrderLongPress(ExternalDelivery order) {
    if (!_isEligibleForTrip(order)) return;
    if (!_selectionMode) {
      _enterSelectionMode();
    }
    _toggleSelection(order);
  }

  Future<void> _showStorePicker() async {
    List<String> stores = [];
    bool loading = true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            if (loading) {
              _repository.fetchStoreNames().then((names) {
                setModal(() {
                  stores = names;
                  loading = false;
                });
              });
            }

            final currentStore =
                ref.read(appControllerProvider).selectedStoreName;

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(ctx).padding.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'Filter by Store',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.nightBlue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Select a store to filter orders, or choose All Stores.',
                    style: TextStyle(fontSize: 13, color: Colors.black45),
                  ),
                  const SizedBox(height: 16),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.oceanBlue,
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
                                  : Colors.black38,
                            ),
                            title: Text(
                              store,
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

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    final selectedStore = app.selectedStoreName;

    ref.listen(
      appControllerProvider.select((c) => c.languageCode),
      (previous, next) {
        if (previous != null && previous != next) {
          _lastStoreName = null;
          _pagingController.refresh();
        }
      },
    );

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        body: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            final bgColor = theme.scaffoldBackgroundColor;
            return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                bgColor,
                Color.alphaBlend(
                  theme.colorScheme.secondary.withValues(alpha: 0.08),
                  bgColor,
                ),
                Color.alphaBlend(
                  theme.colorScheme.tertiary.withValues(alpha: 0.06),
                  bgColor,
                ),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              const _LocationBackdropShapes(),
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(selectedStore),
                    const SizedBox(height: 10),
                    if (!_selectionMode)
                      _buildSearchBar(),
                    Expanded(
                      child: _searchQuery.isNotEmpty
                          ? _buildSearchResults()
                          : RefreshIndicator(
                        color: AppTheme.oceanBlue,
                        onRefresh: _refresh,
                        child: PagedListView<int, LocationListItem>(
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            20,
                            4,
                            20,
                            _selectionMode ? 100 : 20,
                          ),
                          pagingController: _pagingController,
                          builderDelegate:
                              PagedChildBuilderDelegate<LocationListItem>(
                                itemBuilder: (context, item, index) {
                                  if (item is StoreHeader) {
                                    return _StoreHeaderTile(
                                      storeName: item.storeName,
                                    );
                                  }
                                  if (item is OrderRow) {
                                    return _OrderCard(
                                      order: item.order,
                                      busy:
                                          _submittingOrderIds.contains(
                                            item.order.name,
                                          ) ||
                                          _creatingTrip,
                                      selected: _selectedOrderIds.contains(
                                        item.order.name,
                                      ),
                                      selectionMode: _selectionMode,
                                      onTap: () => _handleOrderTap(item.order),
                                      onLongPress: () =>
                                          _handleOrderLongPress(item.order),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                                firstPageProgressIndicatorBuilder: (_) =>
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 20,
                                      ),
                                      child: SkeletonLoader(
                                        itemCount: 4,
                                        spacing: 12,
                                      ),
                                    ),
                                newPageProgressIndicatorBuilder: (_) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                            width: 20,
                                            height: 20,
                                            decoration: BoxDecoration(
                                              color: AppTheme.oceanBlue
                                                  .withValues(alpha: 0.12),
                                              shape: BoxShape.circle,
                                            ),
                                          )
                                          .animate(
                                            onPlay: (controller) =>
                                                controller.repeat(),
                                          )
                                          .shimmer(
                                            duration: 800.ms,
                                            color: AppTheme.oceanBlue
                                                .withValues(alpha: 0.3),
                                          ),
                                    ],
                                  ),
                                ),
                                noItemsFoundIndicatorBuilder: (_) =>
                                    const _EmptyState(),
                                firstPageErrorIndicatorBuilder: (_) =>
                                    _ErrorState(
                                      error: _pagingController.error,
                                      onRetry: _pagingController.refresh,
                                    ),
                                newPageErrorIndicatorBuilder: (_) =>
                                    _ErrorState(
                                      error: _pagingController.error,
                                      onRetry: _pagingController.refresh,
                                    ),
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_selectionMode) _buildSelectionBottomBar(),
            ],
          ),
        );
          },
        ),
      ),
    );
  }

  List<LocationListItem> _filteredItems() {
    final query = _searchQuery.toLowerCase().trim();
    if (query.isEmpty) return _pagingController.itemList ?? [];
    final result = <LocationListItem>[];
    StoreHeader? pendingHeader;
    for (final item in _pagingController.itemList ?? <LocationListItem>[]) {
      if (item is StoreHeader) {
        pendingHeader = item;
      } else if (item is OrderRow) {
        final o = item.order;
        final matches = o.name.toLowerCase().contains(query) ||
            o.customerName.toLowerCase().contains(query) ||
            o.storeName.toLowerCase().contains(query);
        if (matches) {
          if (pendingHeader != null) {
            result.add(pendingHeader);
            pendingHeader = null;
          }
          result.add(item);
        }
      }
    }
    return result;
  }

  Widget _buildSearchResults() {
    final items = _filteredItems();
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: FrostCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 48,
                color: AppTheme.mango.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 12),
              const Text(
                'No orders found',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.nightBlue,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'No results for "$_searchQuery"',
                style: const TextStyle(fontSize: 13, color: Colors.black45),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 4, 20, _selectionMode ? 100 : 20),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is StoreHeader) {
          return _StoreHeaderTile(storeName: item.storeName);
        }
        if (item is OrderRow) {
          return _OrderCard(
            order: item.order,
            busy: _submittingOrderIds.contains(item.order.name) || _creatingTrip,
            selected: _selectedOrderIds.contains(item.order.name),
            selectionMode: _selectionMode,
            onTap: () => _handleOrderTap(item.order),
            onLongPress: () => _handleOrderLongPress(item.order),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A0A1D3A),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _searchQuery = v),
          style: const TextStyle(fontSize: 14, color: AppTheme.nightBlue),
          decoration: InputDecoration(
            hintText: 'Search by order ID or customer…',
            hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 20,
              color: Colors.black38,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Colors.black38,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String? selectedStore) {
    if (_selectionMode) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: _exitSelectionMode,
              tooltip: 'Cancel selection',
            ),
            Expanded(
              child: Text(
                '${_selectedOrderIds.length} order${_selectedOrderIds.length == 1 ? '' : 's'} selected',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.nightBlue,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.store_rounded, color: AppTheme.nightBlue),
              tooltip: 'Change location',
              onPressed: () => _showStorePicker(),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Orders by Location',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.nightBlue,
                  ),
                ),
                Text(
                  selectedStore ?? 'All Stores',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.store_rounded, color: AppTheme.nightBlue),
            tooltip: 'Change location',
            onPressed: () => _showStorePicker(),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.oceanBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            disabledBackgroundColor: AppTheme.oceanBlue.withValues(alpha: 0.5),
          ),
          onPressed: _creatingTrip ? null : _handleCreateTrip,
          child: _creatingTrip
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  '${_selectedOrderIds.length} order${_selectedOrderIds.length == 1 ? '' : 's'} selected → Create Trip',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
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
    required this.busy,
    required this.onTap,
    required this.selected,
    required this.selectionMode,
    required this.onLongPress,
  });
  final ExternalDelivery order;
  final bool busy;
  final VoidCallback onTap;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onLongPress;

  String _formatDate(String raw) {
    if (raw.length < 10) return raw;
    final parts = raw.substring(0, 10).split('-');
    if (parts.length != 3) return raw.substring(0, 10);
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
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
                        color: selected ? AppTheme.oceanBlue : Colors.black38,
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
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 14, top: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppTheme.nightBlue,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 13,
                            color: Colors.black45,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            order.customerName,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.schedule,
                            size: 13,
                            color: Colors.black45,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(order.modified),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Status badge
                if (busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.oceanBlue,
                    ),
                  )
                else
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
            const Text(
              'No orders found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.nightBlue,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pull down to refresh',
              style: TextStyle(fontSize: 13, color: Colors.black45),
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
              style: const TextStyle(fontSize: 13, color: Colors.black54),
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

// ---------------------------------------------------------------------------
// Backdrop shapes
// ---------------------------------------------------------------------------

class _LocationBackdropShapes extends StatelessWidget {
  const _LocationBackdropShapes();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: -60,
            top: -70,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: AppTheme.oceanBlue.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: -35,
            top: 110,
            child: Transform.rotate(
              angle: 0.8,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppTheme.mango.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ),
          Positioned(
            left: 40,
            bottom: -60,
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                color: AppTheme.mint.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
