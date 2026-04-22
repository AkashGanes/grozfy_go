import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/models/app_models.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';

class OrderListingScreen extends StatefulWidget {
  const OrderListingScreen({super.key});

  @override
  State<OrderListingScreen> createState() => _OrderListingScreenState();
}

class _OrderListingScreenState extends State<OrderListingScreen> {
  static const int _pageSize = 8;

  late final ExternalDeliveryRepository _repository;
  late final PagingController<int, DeliveryOrder> _pagingController;
  AppController? _app;

  @override
  void initState() {
    super.initState();
    _repository = ExternalDeliveryRepository();
    _pagingController = PagingController<int, DeliveryOrder>(firstPageKey: 0)
      ..addPageRequestListener(_fetchPage);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = AppScope.of(context);
  }

  @override
  void dispose() {
    _pagingController.dispose();
    super.dispose();
  }

  Future<void> _fetchPage(int pageKey) async {
    final app = _app;
    if (app == null) {
      _pagingController.error = 'App controller is not available';
      return;
    }

    try {
      final summaries = await _repository.fetchPage(
        limitStart: pageKey,
        limitPageLength: _pageSize,
        orderBy: 'modified desc',
        filters: <List<dynamic>>[
          <dynamic>['External Delivery', 'status', '=', 'Pending'],
        ],
      );

      final pageOrders = await Future.wait(
        summaries.map((summary) async {
          try {
            final detail = await _repository.fetchDetail(summary.name);
            return app.buildDeliveryOrderFromDetail(detail);
          } catch (e) {
            if (mounted) {
              debugPrint(
                'fetch_available_order_detail_warn: ${summary.name} $e',
              );
            }
            return null;
          }
        }),
      );

      final orders = pageOrders.whereType<DeliveryOrder>().toList()
        ..sort((a, b) {
          final compareDistance = a.distanceKm.compareTo(b.distanceKm);
          if (compareDistance != 0) {
            return compareDistance;
          }
          return a.orderId.compareTo(b.orderId);
        });

      final isLastPage = summaries.length < _pageSize;
      if (isLastPage) {
        _pagingController.appendLastPage(orders);
      } else {
        _pagingController.appendPage(orders, pageKey + summaries.length);
      }
    } catch (e) {
      _pagingController.error = e;
    }
  }

  Future<void> _refresh() async {
    _pagingController.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Available Orders',
      subtitle: 'Browse nearby orders before accepting',
      scrollable: false,
      child: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: Colors.orange,
              child: PagedListView<int, DeliveryOrder>(
                pagingController: _pagingController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                builderDelegate: PagedChildBuilderDelegate<DeliveryOrder>(
                  firstPageProgressIndicatorBuilder: (_) =>
                      const Center(child: CircularProgressIndicator()),
                  newPageProgressIndicatorBuilder: (_) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  firstPageErrorIndicatorBuilder: (_) =>
                      _ErrorState(onRetry: _pagingController.refresh),
                  newPageErrorIndicatorBuilder: (_) => _ErrorState(
                    onRetry: _pagingController.retryLastFailedRequest,
                  ),
                  noItemsFoundIndicatorBuilder: (_) => const _EmptyState(),
                  itemBuilder: (context, order, index) {
                    return _OrderCard(
                          order: order,
                          onTap: () {
                            Navigator.of(context).pushNamed(
                              AppRoutes.orderDetails,
                              arguments: order,
                            );
                          },
                        )
                        .animate()
                        .fadeIn(delay: (index * 35).ms, duration: 220.ms)
                        .slideY(begin: 0.04, end: 0);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final DeliveryOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FrostCard(
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    order.orderId,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      order.assignmentStatus.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _infoRow(Icons.store, 'Store: ${order.storeName}'),
              _infoRow(Icons.person, 'Customer: ${order.customerName}'),
              _infoRow(Icons.location_on, 'Drop: ${order.deliveryAddress}'),
              _infoRow(Icons.route, 'Distance: ${order.distanceKm} km'),
              _infoRow(
                Icons.currency_rupee,
                'Earnings: Rs. ${order.estimatedEarnings.toStringAsFixed(0)}',
              ),
              const SizedBox(height: 8),
              const Text(
                'Items:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              ...order.orderItems.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text(
                    '${item.name} x${item.quantity} - Rs. ${(item.price * item.quantity).toStringAsFixed(0)}',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onTap,
                  child: const Text('View Details'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_shipping_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Text('No available orders'),
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
