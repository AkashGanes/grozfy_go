import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../core/navigation/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../model/external_delivery.dart';
import '../repository/external_delivery_repository.dart';

class ExternalDeliveryTripListScreen extends StatefulWidget {
  const ExternalDeliveryTripListScreen({super.key});

  @override
  State<ExternalDeliveryTripListScreen> createState() =>
      _ExternalDeliveryTripListScreenState();
}

class _ExternalDeliveryTripListScreenState
    extends State<ExternalDeliveryTripListScreen> {
  ExternalDeliveryRepository? _repository;
  PagingController<int, TripListItem>? _pagingController;
  String? _lastDriver;

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
      final trips = await _repository!.fetchTripPage(limitStart: pageKey);
      final items = <TripListItem>[];
      for (final trip in trips) {
        if (trip.driver != _lastDriver) {
          items.add(DriverHeader(trip.driver));
          _lastDriver = trip.driver;
        }
        items.add(TripRow(trip));
      }
      final isLast = trips.length < ExternalDeliveryRepository.pageSize;
      if (isLast) {
        _pagingController!.appendLastPage(items);
      } else {
        _pagingController!.appendPage(items, pageKey + trips.length);
      }
    } catch (e) {
      _pagingController!.error = e;
    }
  }

  Future<void> _refresh() async {
    _lastDriver = null;
    _pagingController!.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _pagingController;
    if (controller == null) return const SizedBox.shrink();

    return AppShell(
      title: 'External Delivery Trips',
      subtitle: 'All trips grouped by driver',
      scrollable: false,
      padding: EdgeInsets.zero,
      child: RefreshIndicator(
        color: AppTheme.oceanBlue,
        onRefresh: _refresh,
        child: PagedListView<int, TripListItem>(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          pagingController: controller,
          builderDelegate: PagedChildBuilderDelegate<TripListItem>(
            itemBuilder: (context, item, index) {
              if (item is DriverHeader) {
                return Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 8),
                  child: SectionLabel(item.driver),
                );
              }
              if (item is TripRow) {
                return _TripCard(
                  trip: item.trip,
                  onTap: () => Navigator.of(context).pushNamed(
                    AppRoutes.externalDeliveryTripDetails,
                    arguments: item.trip.name,
                  ),
                );
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

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.onTap});

  final ExternalDeliveryTripSummary trip;
  final VoidCallback onTap;

  String _formatDate(String raw) {
    if (raw.length < 10) return raw;
    final parts = raw.substring(0, 10).split('-');
    if (parts.length != 3) return raw.substring(0, 10);
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  String _docstatusLabel(int docstatus) {
    switch (docstatus) {
      case 0:
        return 'Draft';
      case 1:
        return 'Submitted';
      case 2:
        return 'Cancelled';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: FrostCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.local_shipping_outlined, color: AppTheme.oceanBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.nightBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Date: ${_formatDate(trip.tripDate)} • Stops: ${trip.completedStops}/${trip.totalStops}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.oceanBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.oceanBlue.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  _docstatusLabel(trip.docstatus),
                  style: const TextStyle(
                    color: AppTheme.oceanBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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
              Icons.local_shipping_outlined,
              size: 52,
              color: AppTheme.oceanBlue.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'No trips found',
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
