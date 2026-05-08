import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../core/navigation/app_routes.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/offline_trip_manager.dart';
import '../../../core/state/app_scope.dart';
import '../../../core/state/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../model/external_delivery.dart';
import '../repository/external_delivery_repository.dart';

class ExternalDeliveryTripListScreen extends ConsumerStatefulWidget {
  const ExternalDeliveryTripListScreen({super.key});

  @override
  ConsumerState<ExternalDeliveryTripListScreen> createState() =>
      _ExternalDeliveryTripListScreenState();
}

class _ExternalDeliveryTripListScreenState
    extends ConsumerState<ExternalDeliveryTripListScreen> {
  ExternalDeliveryRepository? _repository;
  PagingController<int, TripListItem>? _pagingController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _lastDriver;
  // Run the background "warm everything" prefetch only once per app session.
  // Subsequent navigations to this screen don't re-trigger it.
  static bool _prefetchTriggered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pagingController != null) return;
    _repository = ExternalDeliveryRepository();
    _pagingController = PagingController(firstPageKey: 0)
      ..addPageRequestListener(_fetchPage);

    // First time the trip list opens online this session, kick off a
    // background prefetch of every trip's full details + stops + orders.
    // This way the driver can go offline at any point and details still
    // open. We don't await — UI stays responsive while it runs.
    if (!_prefetchTriggered && ConnectivityService().isConnected) {
      _prefetchTriggered = true;
      unawaited(OfflineTripManager().downloadAllTripsAtTripStart());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pagingController?.dispose();
    super.dispose();
  }

  Future<void> _fetchPage(int pageKey) async {
    // Offline: serve the whole cached list on the first page request,
    // then mark as last so paging stops. We don't paginate the cache.
    if (!ConnectivityService().isConnected) {
      _serveFromCache(pageKey);
      return;
    }

    try {
      final trips = await _repository!.fetchTripPage(limitStart: pageKey);
      ConnectivityService().reportNetworkSuccess();
      // Warm the cache on every successful page so the list survives a
      // future offline open.
      await OfflineTripManager().cacheTripSummariesPage(trips);
      final items = trips.map((t) => TripRow(t) as TripListItem).toList();
      final isLast = trips.length < ExternalDeliveryRepository.pageSize;
      if (isLast) {
        _pagingController!.appendLastPage(items);
      } else {
        _pagingController!.appendPage(items, pageKey + trips.length);
      }
    } catch (e) {
      if (_isNetworkError(e)) {
        // The package listener can lag — flip the connectivity flag
        // ourselves so the offline banner shows immediately.
        ConnectivityService().reportNetworkFailure();
        _serveFromCache(pageKey);
        return;
      }
      _pagingController!.error = e;
    }
  }

  void _serveFromCache(int pageKey) {
    if (pageKey == 0) {
      final cached = OfflineTripManager().getCachedTripSummaries();
      _pagingController!.appendLastPage(
        cached.map((t) => TripRow(t) as TripListItem).toList(),
      );
    } else {
      _pagingController!.appendLastPage(const []);
    }
  }

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
    final ColorScheme scheme = Theme.of(context).colorScheme;
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
            hintStyle: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 18,
            ),
            suffixIcon: _searchQuery.trim().isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    icon: Icon(
                      Icons.close_rounded,
                      color: scheme.onSurface.withValues(alpha: 0.5),
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
        newPageProgressIndicatorBuilder: (_) => Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
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
    final app = ref.watch(appControllerProvider);

    ref.listen(
      appControllerProvider.select((c) => c.languageCode),
      (previous, next) {
        if (previous != null && previous != next) {
          _pagingController?.refresh();
        }
      },
    );

    final controller = _pagingController;
    if (controller == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return AppShell(
      title: app.t('external_delivery_trips'),
      subtitle: app.t('trips_grouped_by_driver'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Icon(
            Icons.local_shipping_outlined,
            color: colorScheme.primary,
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
              color: colorScheme.primary,
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

  String _docstatusLabel(BuildContext context, int docstatus) {
    final app = AppScope.of(context);
    switch (docstatus) {
      case 0:
        return app.t('draft');
      case 1:
        return app.t('submitted');
      case 2:
        return app.t('cancelled');
      default:
        return app.t('unknown');
    }
  }

  Color _getStatusColor(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized.contains('completed')) {
      return const Color(0xFF2E7D32);
    } else if (normalized.contains('in transit') || normalized.contains('ongoing')) {
      return const Color(0xFFE65100);
    } else if (normalized.contains('draft')) {
      return const Color(0xFF757575);
    } else if (normalized.contains('failed')) {
      return const Color(0xFFD32F2F);
    }
    return const Color(0xFF757575);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final total = trip.totalStops;
    final done = trip.completedStops.clamp(0, total > 0 ? total : 0);
    final progress = total > 0 ? done / total : 0.0;
    final isComplete = total > 0 && done >= total;
    final progressColor = isComplete ? const Color(0xFF2E7D32) : colorScheme.primary;

    final Color badgeColor;
    switch (trip.docstatus) {
      case 2:
        badgeColor = Colors.red;
      case 1:
        badgeColor = colorScheme.primary;
      default:
        badgeColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    }

    final statusColor = _getStatusColor(trip.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: FrostCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.local_shipping_outlined,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(trip.tripDate),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      trip.status.isEmpty ? 'Draft' : trip.status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Spacer(),
                  Text(
                    '$done/$total stops',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isComplete
                          ? const Color(0xFF2E7D32)
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  minHeight: 6,
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: FrostCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_shipping_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'No trips found',
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
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
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
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 10,
                          width: 220,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
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
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return FrostCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 12),
          Text(
            'No trip found for this ID',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try another Trip ID',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
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
