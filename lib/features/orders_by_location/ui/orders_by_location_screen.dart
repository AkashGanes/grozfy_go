import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../model/external_delivery.dart';
import '../repository/external_delivery_repository.dart';

class OrdersByLocationScreen extends StatefulWidget {
  const OrdersByLocationScreen({super.key});

  @override
  State<OrdersByLocationScreen> createState() => _OrdersByLocationScreenState();
}

class _OrdersByLocationScreenState extends State<OrdersByLocationScreen> {
  ExternalDeliveryRepository? _repository;
  PagingController<int, LocationListItem>? _pagingController;
  String? _lastStoreName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pagingController != null) return;
    _repository = ExternalDeliveryRepository();
    _pagingController = PagingController(firstPageKey: 0)
      ..addPageRequestListener(_fetchPage);
  }

  @override
  void dispose() {
    _pagingController?.dispose();
    super.dispose();
  }

  Future<void> _fetchPage(int pageKey) async {
    try {
      final orders = await _repository!.fetchPage(limitStart: pageKey);
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
        _pagingController!.appendLastPage(items);
      } else {
        _pagingController!.appendPage(items, pageKey + orders.length);
      }
    } catch (e) {
      _pagingController!.error = e;
    }
  }

  Future<void> _refresh() async {
    _lastStoreName = null;
    _pagingController!.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _pagingController;
    if (controller == null) return const SizedBox.shrink();

    return AppShell(
      title: 'Orders by Location',
      subtitle: 'All deliveries grouped by store',
      scrollable: false,
      padding: EdgeInsets.zero,
      child: RefreshIndicator(
        color: AppTheme.oceanBlue,
        onRefresh: _refresh,
        child: PagedListView<int, LocationListItem>(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          pagingController: controller,
          builderDelegate: PagedChildBuilderDelegate<LocationListItem>(
            itemBuilder: (context, item, index) {
              if (item is StoreHeader) {
                return _StoreHeaderTile(storeName: item.storeName);
              }
              if (item is OrderRow) {
                return _OrderCard(order: item.order);
              }
              return const SizedBox.shrink();
            },
            firstPageProgressIndicatorBuilder: (_) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.oceanBlue),
              ),
            ),
            newPageProgressIndicatorBuilder: (_) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppTheme.oceanBlue,
                  strokeWidth: 2,
                ),
              ),
            ),
            noItemsFoundIndicatorBuilder: (_) => const _EmptyState(),
            firstPageErrorIndicatorBuilder: (_) => _ErrorState(
              error: controller.error,
              onRetry: controller.refresh,
            ),
            newPageErrorIndicatorBuilder: (_) => _ErrorState(
              error: controller.error,
              onRetry: controller.retryLastFailedRequest,
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
  const _OrderCard({required this.order});
  final ExternalDelivery order;

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
      child: FrostCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 14, top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
              ),
            ),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withValues(alpha: 0.35)),
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
