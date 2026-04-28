import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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
    _searchController.dispose();
    _pagingController?.dispose();
    super.dispose();
  }

  Future<void> _fetchPage(int pageKey) async {
    try {
      final trips = await _repository!.fetchTripPage(limitStart: pageKey);
      final items = trips.map((t) => TripRow(t) as TripListItem).toList();
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
    _pagingController!.refresh();
  }

  List<ExternalDeliveryTripSummary> _filteredTrips(
    PagingController<int, TripListItem> controller,
  ) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final items = controller.itemList ?? const <TripListItem>[];
    return items
        .whereType<TripRow>()
        .map((item) => item.trip)
        .where((trip) => trip.name.toLowerCase().contains(q))
        .toList();
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
      child: FrostCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        child: TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _searchQuery = value),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: InputBorder.none,
            hintText: 'Search Trip ID',
            hintStyle: const TextStyle(color: Colors.black45),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: AppTheme.oceanBlue,
              size: 18,
            ),
            suffixIcon: _searchQuery.trim().isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.black45,
                      size: 18,
                    ),
                  ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.04, end: 0);
  }

  Widget _buildPagedList(PagingController<int, TripListItem> controller) {
    return PagedListView<int, TripListItem>(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      pagingController: controller,
      builderDelegate: PagedChildBuilderDelegate<TripListItem>(
        itemBuilder: (context, item, index) {
          final delay = (index * 45).clamp(0, 320);
          if (item is TripRow) {
            return _TripCard(
                  trip: item.trip,
                  onTap: () => Navigator.of(context).pushNamed(
                    AppRoutes.externalDeliveryTripDetails,
                    arguments: item.trip.name,
                  ),
                )
                .animate()
                .fadeIn(delay: delay.ms, duration: 240.ms)
                .slideY(begin: 0.06, end: 0)
                .scale(
                  begin: const Offset(0.985, 0.985),
                  end: const Offset(1, 1),
                  duration: 240.ms,
                  curve: Curves.easeOutCubic,
                );
          }
          return const SizedBox.shrink();
        },
        firstPageProgressIndicatorBuilder: (_) => const _ListLoadingState(),
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
        firstPageErrorIndicatorBuilder: (_) =>
            _ErrorState(error: controller.error, onRetry: controller.refresh),
        newPageErrorIndicatorBuilder: (_) => _ErrorState(
          error: controller.error,
          onRetry: controller.retryLastFailedRequest,
        ),
      ),
    );
  }

  Widget _buildFilteredList(PagingController<int, TripListItem> controller) {
    if (controller.itemList == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: _ListLoadingState(),
      );
    }

    final results = _filteredTrips(controller);
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: _SearchEmptyState(),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final delay = (index * 45).clamp(0, 320);
        final trip = results[index];
        return _TripCard(
              trip: trip,
              onTap: () => Navigator.of(context).pushNamed(
                AppRoutes.externalDeliveryTripDetails,
                arguments: trip.name,
              ),
            )
            .animate()
            .fadeIn(delay: delay.ms, duration: 240.ms)
            .slideY(begin: 0.05, end: 0)
            .scale(
              begin: const Offset(0.985, 0.985),
              end: const Offset(1, 1),
              duration: 230.ms,
              curve: Curves.easeOutCubic,
            );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _pagingController;
    if (controller == null) return const SizedBox.shrink();

    return AppShell(
      title: 'External Delivery Trips',
      subtitle: 'My trips',
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 10),
          child: Icon(
            Icons.local_shipping_outlined,
            color: AppTheme.oceanBlue,
            size: 22,
          ),
        ),
      ],
      scrollable: false,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.oceanBlue,
              onRefresh: _refresh,
              child: _searchQuery.trim().isEmpty
                  ? _buildPagedList(controller)
                  : _buildFilteredList(controller),
            ),
          ),
        ],
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

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return 'Draft';
      case 'scheduled':
        return 'Scheduled';
      case 'in progress':
      case 'in_transit':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.isEmpty ? 'Unknown' : status;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return Colors.grey;
      case 'scheduled':
        return Colors.blue;
      case 'in progress':
      case 'in_transit':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
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
              const Icon(
                Icons.local_shipping_outlined,
                color: AppTheme.oceanBlue,
              ),
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(trip.status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _statusColor(trip.status).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      _statusLabel(trip.status),
                      style: TextStyle(
                        color: _statusColor(trip.status),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
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

class _ListLoadingState extends StatelessWidget {
  const _ListLoadingState();

  @override
  Widget build(BuildContext context) {
    Widget skeletonCard(int i) {
      return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FrostCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppTheme.oceanBlue.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 12,
                          width: 150,
                          decoration: BoxDecoration(
                            color: AppTheme.oceanBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 10,
                          width: 220,
                          decoration: BoxDecoration(
                            color: AppTheme.oceanBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .animate(onPlay: (controller) => controller.repeat())
          .shimmer(
            duration: (1000 + (i * 120)).ms,
            color: AppTheme.oceanBlue.withValues(alpha: 0.12),
          );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [skeletonCard(0), skeletonCard(1), skeletonCard(2)],
      ),
    ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.03, end: 0);
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return FrostCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 18,
            color: AppTheme.oceanBlue.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 12),
          const Text(
            'No trip found for this ID',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.nightBlue,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Try another Trip ID',
            style: TextStyle(fontSize: 13, color: Colors.black45),
          ),
        ],
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
