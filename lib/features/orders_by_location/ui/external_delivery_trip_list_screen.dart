import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../core/navigation/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/offline_trip_manager.dart';
import '../../../core/state/app_scope.dart';
import '../../../core/state/providers.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/offline_status_indicator.dart';
import '../../kyc/widgets/kyc_form_widgets.dart';
import '../model/external_delivery.dart';
import '../repository/external_delivery_repository.dart';

/// Driver-facing lifecycle state of a trip row.
///
/// The backend exposes two overlapping signals — Frappe's `docstatus`
/// (0 draft / 1 submitted / 2 cancelled) and the trip's own `status` string —
/// plus the stop counters. Drivers only care about the outcome, so all three
/// collapse into one enum here.
enum _TripState { draft, submitted, inProgress, completed, cancelled }

/// The chips above the list. `submitted` is the "still open" bucket: it covers
/// draft, submitted and in-progress trips, because from the driver's point of
/// view they are all trips that haven't finished yet.
enum _TripFilter { all, completed, submitted, cancelled }

/// Screen-scoped color tokens.
///
/// Kept local rather than pushed into `AppTheme` so the purple accent stays on
/// this screen instead of repainting every other one. Light mode is the spec
/// verbatim; dark mode lifts each tone so it stays readable on a dark surface.
class _Palette {
  const _Palette({
    required this.bg,
    required this.card,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.primary,
    required this.success,
    required this.danger,
    required this.info,
    required this.warning,
    required this.neutral,
    required this.shadow,
  });

  final Color bg;
  final Color card;
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color primary;
  final Color success;
  final Color danger;
  final Color info;
  final Color warning;
  final Color neutral;
  final Color shadow;

  static const _light = _Palette(
    bg: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF6F7FB),
    border: Color(0xFFEEF0F6),
    textPrimary: Color(0xFF101828),
    textSecondary: Color(0xFF667085),
    primary: Color(0xFF6C4DFF),
    success: Color(0xFF16A34A),
    danger: Color(0xFFDC2626),
    info: Color(0xFF2563EB),
    warning: Color(0xFFF59E0B),
    neutral: Color(0xFF98A2B3),
    shadow: Color(0x0F101828),
  );

  static const _dark = _Palette(
    bg: Color(0xFF0E1017),
    card: Color(0xFF171A23),
    surfaceAlt: Color(0xFF1E212C),
    border: Color(0xFF272B37),
    textPrimary: Color(0xFFF2F4F7),
    textSecondary: Color(0xFF98A2B3),
    primary: Color(0xFF9B85FF),
    success: Color(0xFF4ADE80),
    danger: Color(0xFFFF8080),
    info: Color(0xFF7BA6FF),
    warning: Color(0xFFFBBF24),
    neutral: Color(0xFF7A828F),
    shadow: Color(0x33000000),
  );

  /// Accents stay fixed, but the page/card/border tones come from the active
  /// theme so this screen sits on the same background as every other page
  /// (including a user-overridden scaffold colour) instead of a flat white.
  static _Palette of(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final base = dark ? _dark : _light;
    return _Palette(
      bg: theme.scaffoldBackgroundColor,
      card: dark ? theme.colorScheme.surface : Colors.white,
      surfaceAlt: dark
          ? base.surfaceAlt
          : Color.alphaBlend(
              theme.colorScheme.primary.withValues(alpha: 0.04),
              const Color(0xFFF6F7FB),
            ),
      border: theme.colorScheme.outlineVariant,
      textPrimary: theme.colorScheme.onSurface,
      textSecondary: theme.colorScheme.onSurfaceVariant,
      primary: base.primary,
      success: base.success,
      danger: base.danger,
      info: base.info,
      warning: base.warning,
      neutral: base.neutral,
      shadow: base.shadow,
    );
  }

  Color stateColor(_TripState state) => switch (state) {
    _TripState.completed => success,
    _TripState.submitted => info,
    _TripState.cancelled => danger,
    _TripState.inProgress => warning,
    _TripState.draft => neutral,
  };
}

_TripState _stateOf(ExternalDeliveryTripSummary t) {
  final s = t.status.trim().toLowerCase();
  if (t.docstatus == 2 || s == 'cancelled') return _TripState.cancelled;
  if (s == 'completed' || (t.totalStops > 0 && t.completedStops >= t.totalStops)) {
    return _TripState.completed;
  }
  if (t.completedStops > 0 ||
      s == 'in progress' ||
      s == 'in_progress' ||
      s == 'started') {
    return _TripState.inProgress;
  }
  return t.docstatus == 0 ? _TripState.draft : _TripState.submitted;
}

String _stateLabel(BuildContext context, _TripState state) {
  final app = AppScope.of(context);
  return switch (state) {
    _TripState.completed => 'Completed',
    _TripState.inProgress => 'In Progress',
    _TripState.submitted => app.t('submitted'),
    _TripState.cancelled => app.t('cancelled'),
    _TripState.draft => app.t('draft'),
  };
}

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
  _TripFilter _filter = _TripFilter.all;
  DateTimeRange? _dateRange;
  // Guards the background page pulls that run while a filter is active, so a
  // rebuild mid-fetch doesn't fire a second request for the same page.
  bool _filterFetchInFlight = false;
  // Run the background "warm everything" prefetch only once per app session.
  // Subsequent navigations to this screen don't re-trigger it.
  static bool _prefetchTriggered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pagingController != null) return;
    _repository = ExternalDeliveryRepository();
    _pagingController = PagingController(firstPageKey: 0)
      ..addPageRequestListener(_fetchPage)
      ..addListener(_onPagingUpdate);

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
    _pagingController
      ?..removeListener(_onPagingUpdate)
      ..dispose();
    super.dispose();
  }

  /// The paged list rebuilds itself when a page lands, but the stat tiles and
  /// the filtered list are built here — without this they'd stay frozen at
  /// their first-frame values (0 trips) until some other setState ran.
  void _onPagingUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _fetchPage(int pageKey) async {
    // Offline: serve the whole cached list on the first page request,
    // then mark as last so paging stops. We don't paginate the cache.
    if (!ConnectivityService().isConnected) {
      _serveFromCache(pageKey);
      _filterFetchInFlight = false;
      return;
    }

    try {
      final trips = await _repository!.fetchTripPage(limitStart: pageKey);
      if (!mounted) return;
      final controller = _pagingController;
      if (controller == null) return;
      ConnectivityService().reportNetworkSuccess();
      // Warm the cache on every successful page so the list survives a
      // future offline open.
      await OfflineTripManager().cacheTripSummariesPage(trips);
      if (!mounted) return;
      final items = trips.map((t) => TripRow(t) as TripListItem).toList();
      final isLast = trips.length < ExternalDeliveryRepository.pageSize;
      if (isLast) {
        controller.appendLastPage(items);
      } else {
        controller.appendPage(items, pageKey + trips.length);
      }
    } catch (e) {
      if (_isNetworkError(e)) {
        // The package listener can lag — flip the connectivity flag
        // ourselves so the offline banner shows immediately.
        ConnectivityService().reportNetworkFailure();
        if (!mounted) return;
        _serveFromCache(pageKey);
        return;
      }
      if (!mounted) return;
      _pagingController?.error = e;
    } finally {
      _filterFetchInFlight = false;
    }
  }

  void _serveFromCache(int pageKey) {
    final controller = _pagingController;
    if (controller == null || !mounted) return;
    if (pageKey == 0) {
      final cached = OfflineTripManager().getCachedTripSummaries();
      controller.appendLastPage(
        cached.map((t) => TripRow(t) as TripListItem).toList(),
      );
    } else {
      controller.appendLastPage(const []);
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

  /// Every trip fetched so far. Search, chips and the date range all filter
  /// this loaded set client-side — the endpoint has no filter parameters.
  List<ExternalDeliveryTripSummary> _loadedTrips(
    PagingController<int, TripListItem> controller,
  ) {
    final items = controller.itemList ?? const <TripListItem>[];
    return items.whereType<TripRow>().map((item) => item.trip).toList();
  }

  /// While a filter is on, the paged list is replaced by a plain filtered
  /// list, so nothing drives pagination any more — a match sitting on page 3
  /// would look like "no results". Keep pulling pages in the background until
  /// the feed is exhausted, one request at a time.
  void _keepLoadingWhileFiltering(
    PagingController<int, TripListItem> controller,
  ) {
    if (!_isFiltering || _filterFetchInFlight) return;
    final int? next = controller.nextPageKey;
    if (next == null || controller.error != null) return;
    _filterFetchInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _filterFetchInFlight = false;
        return;
      }
      controller.notifyPageRequestListeners(next);
    });
  }

  bool get _isFiltering =>
      _searchQuery.trim().isNotEmpty ||
      _filter != _TripFilter.all ||
      _dateRange != null;

  bool _matchesFilter(ExternalDeliveryTripSummary trip) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      final haystack = [trip.name, trip.customerName ?? '', trip.location ?? '']
          .join(' ')
          .toLowerCase();
      if (!haystack.contains(q)) return false;
    }

    if (_filter != _TripFilter.all) {
      final state = _stateOf(trip);
      final matchesChip = switch (_filter) {
        _TripFilter.completed => state == _TripState.completed,
        _TripFilter.cancelled => state == _TripState.cancelled,
        // "Submitted" is the open bucket — anything not finished or cancelled.
        _TripFilter.submitted =>
          state == _TripState.submitted ||
              state == _TripState.draft ||
              state == _TripState.inProgress,
        _TripFilter.all => true,
      };
      if (!matchesChip) return false;
    }

    final range = _dateRange;
    if (range != null) {
      final date = DateTime.tryParse(trip.tripDate);
      if (date == null) return false;
      final day = DateTime(date.year, date.month, date.day);
      final start = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      final end = DateTime(range.end.year, range.end.month, range.end.day);
      if (day.isBefore(start) || day.isAfter(end)) return false;
    }

    return true;
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _dateRange,
      builder: (context, child) {
        final p = _Palette.of(context);
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: p.primary),
          ),
          child: child!,
        );
      },
    );
    if (!mounted || picked == null) return;
    setState(() => _dateRange = picked);
  }

  void _clearFilters() {
    setState(() {
      _filter = _TripFilter.all;
      _dateRange = null;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  String? get _dateRangeLabel {
    final r = _dateRange;
    if (r == null) return null;
    final start = AppDateFormat.date(r.start);
    final end = AppDateFormat.date(r.end);
    return start == end ? start : '$start – $end';
  }

  static String _filterLabel(BuildContext context, _TripFilter f) {
    final app = AppScope.of(context);
    return switch (f) {
      _TripFilter.all => 'All',
      _TripFilter.completed => 'Completed',
      _TripFilter.submitted => app.t('submitted'),
      _TripFilter.cancelled => app.t('cancelled'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);

    ref.listen(appControllerProvider.select((c) => c.languageCode), (
      previous,
      next,
    ) {
      if (previous != null && previous != next) {
        _pagingController?.refresh();
      }
    });

    final controller = _pagingController;
    if (controller == null) return const SizedBox.shrink();

    final p = _Palette.of(context);
    final loaded = _loadedTrips(controller);
    final visible = loaded.where(_matchesFilter).toList();
    _keepLoadingWhileFiltering(controller);

    return Scaffold(
      backgroundColor: p.bg,
      body: Container(
        // Same gradient + backdrop shapes AppShell paints, so this page reads
        // as part of the app instead of a lone white screen.
        decoration: BoxDecoration(gradient: appBackgroundGradient(context)),
        child: Stack(
          children: [
            const AppBackdropShapes(),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const OfflineStatusIndicator(),
                  const SyncStatusBanner(),
                  _Header(
                    palette: p,
                    title: app.t('external_delivery_trips'),
                    subtitle: app.t('trips_grouped_by_driver'),
                    dateActive: _dateRange != null,
                    onBack: () => Navigator.of(context).maybePop(),
                    onCalendar: _pickDateRange,
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      color: p.primary,
                      backgroundColor: p.card,
                      onRefresh: _refresh,
                      child: CustomScrollView(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        slivers: [
                          // Search sits directly under the header — it's the
                          // first thing a driver reaches for, so the stats
                          // tiles come after it rather than above.
                          SliverToBoxAdapter(
                            child: _SearchRow(
                              controller: _searchController,
                              onChanged: (v) =>
                                  setState(() => _searchQuery = v),
                            ),
                          ),
                          if (_dateRangeLabel != null)
                            SliverToBoxAdapter(
                              child: _ActiveDatePill(
                                palette: p,
                                label: _dateRangeLabel!,
                                onClear: () =>
                                    setState(() => _dateRange = null),
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: _StatsRow(palette: p, trips: loaded),
                          ),
                          SliverToBoxAdapter(
                            child: _FilterChipsRow(
                              palette: p,
                              selected: _filter,
                              onSelect: (f) => setState(() => _filter = f),
                            ),
                          ),
                          if (_isFiltering)
                            ..._buildFilteredSlivers(controller, visible, p)
                          else
                            _buildPagedSliver(controller, p),
                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagedSliver(
    PagingController<int, TripListItem> controller,
    _Palette p,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: PagedSliverList<int, TripListItem>(
        pagingController: controller,
        builderDelegate: PagedChildBuilderDelegate<TripListItem>(
          itemBuilder: (context, item, index) {
            if (item is TripRow) return _tripCard(item.trip, p);
            return const SizedBox.shrink();
          },
          firstPageProgressIndicatorBuilder: (_) => _LoadingList(palette: p),
          newPageProgressIndicatorBuilder: (_) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(color: p.primary, strokeWidth: 2),
            ),
          ),
          noItemsFoundIndicatorBuilder: (_) => _EmptyState(
            palette: p,
            icon: Icons.local_shipping_outlined,
            title: 'No trips yet',
            message: 'Pull down to refresh',
          ),
          firstPageErrorIndicatorBuilder: (_) => _ErrorState(
            palette: p,
            error: controller.error,
            onRetry: controller.refresh,
          ),
          newPageErrorIndicatorBuilder: (_) => _ErrorState(
            palette: p,
            error: controller.error,
            onRetry: controller.retryLastFailedRequest,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFilteredSlivers(
    PagingController<int, TripListItem> controller,
    List<ExternalDeliveryTripSummary> visible,
    _Palette p,
  ) {
    if (controller.itemList == null) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverToBoxAdapter(child: _LoadingList(palette: p)),
        ),
      ];
    }

    // More pages are still being pulled in the background, so "nothing found"
    // isn't the truth yet — say we're still looking instead.
    final bool moreComing =
        controller.nextPageKey != null && controller.error == null;

    if (visible.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          sliver: SliverToBoxAdapter(
            child: moreComing
                ? _SearchProgress(palette: p)
                : _EmptyState(
                    palette: p,
                    icon: Icons.search_off_rounded,
                    title: 'No matching trips',
                    message: 'Try a different Trip ID, status or date',
                    actionLabel: 'Clear filters',
                    onAction: _clearFilters,
                  ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _tripCard(visible[index], p),
            childCount: visible.length,
          ),
        ),
      ),
      if (moreComing)
        SliverToBoxAdapter(child: _SearchProgress(palette: p, compact: true)),
    ];
  }

  Widget _tripCard(ExternalDeliveryTripSummary trip, _Palette p) {
    return _TripCard(
      trip: trip,
      palette: p,
      onTap: () => Navigator.of(context).pushNamed(
        AppRoutes.externalDeliveryTripDetails,
        arguments: trip.name,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.dateActive,
    required this.onBack,
    required this.onCalendar,
  });

  final _Palette palette;
  final String title;
  final String subtitle;
  final bool dateActive;
  final VoidCallback onBack;
  final VoidCallback onCalendar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          _IconBox(
            palette: palette,
            icon: Icons.arrow_back_rounded,
            onTap: onBack,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _IconBox(
            palette: palette,
            icon: Icons.calendar_today_rounded,
            active: dateActive,
            onTap: onCalendar,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 220.ms);
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({
    required this.palette,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final _Palette palette;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color fg = active ? palette.primary : palette.textPrimary;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: active
                    ? palette.primary.withValues(alpha: 0.12)
                    : palette.surfaceAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: active
                      ? palette.primary.withValues(alpha: 0.3)
                      : palette.border,
                ),
              ),
              child: Icon(icon, size: 20, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.palette, required this.trips});

  final _Palette palette;
  final List<ExternalDeliveryTripSummary> trips;

  @override
  Widget build(BuildContext context) {
    final states = trips.map(_stateOf).toList();
    final completed = states.where((s) => s == _TripState.completed).length;
    final active = states.where((s) => s == _TripState.inProgress).length;

    // Tiles 2 and 3 are the earnings pair from the spec, but the trip list
    // endpoint doesn't send a payout figure yet. Rather than show two dead
    // "₹—" tiles, fall back to trip counts until any loaded trip carries
    // `earnings`; the moment the backend sends it, the earnings tiles appear.
    final hasEarnings = trips.any((t) => t.earnings != null);
    final now = DateTime.now();
    double sumWhere(bool Function(DateTime) test) => trips
        .where((t) => t.earnings != null)
        .where((t) {
          final d = DateTime.tryParse(t.tripDate);
          return d != null && test(d);
        })
        .fold<double>(0, (sum, t) => sum + t.earnings!);

    final today = sumWhere(
      (d) => d.year == now.year && d.month == now.month && d.day == now.day,
    );
    final month = sumWhere((d) => d.year == now.year && d.month == now.month);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      // IntrinsicHeight so all three tiles adopt the tallest one's height —
      // `stretch` alone would demand infinite height inside the scroll view.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _StatCard(
                palette: palette,
                icon: Icons.local_shipping_rounded,
                tint: palette.primary,
                value: '${trips.length}',
                label: 'Total Trips',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                palette: palette,
                icon: hasEarnings
                    ? Icons.account_balance_wallet_rounded
                    : Icons.check_circle_rounded,
                tint: palette.success,
                value: hasEarnings ? _rupees(today) : '$completed',
                label: hasEarnings ? "Today's Earnings" : 'Completed',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                palette: palette,
                icon: hasEarnings
                    ? Icons.savings_rounded
                    : Icons.timelapse_rounded,
                tint: hasEarnings ? palette.success : palette.warning,
                value: hasEarnings ? _rupees(month) : '$active',
                label: hasEarnings ? 'This Month' : 'In Progress',
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.05, end: 0);
  }
}

/// ₹ with thousands separators, and no decimals for whole amounts.
String _rupees(double value) {
  final bool whole = value == value.roundToDouble();
  final String raw = whole
      ? value.round().toString()
      : value.toStringAsFixed(2);
  final parts = raw.split('.');
  final digits = parts.first;
  final buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '₹${buffer.toString()}${parts.length > 1 ? '.${parts[1]}' : ''}';
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.palette,
    required this.icon,
    required this.tint,
    required this.value,
    required this.label,
  });

  final _Palette palette;
  final IconData icon;
  final Color tint;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: tint),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.2,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      // Same input the New Orders page uses, so search looks and behaves
      // identically across the app.
      child: KycSearchInput(
        controller: controller,
        hint: 'Search Trip ID, Customer, Location',
        onChanged: onChanged,
      ),
    ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.05, end: 0);
  }
}

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({
    required this.palette,
    required this.selected,
    required this.onSelect,
  });

  final _Palette palette;
  final _TripFilter selected;
  final ValueChanged<_TripFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      // Wrap rather than a horizontal ListView so every chip stays reachable
      // on narrow phones instead of scrolling off-screen.
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in _TripFilter.values)
            _FilterChip(
              label: _ExternalDeliveryTripListScreenState._filterLabel(
                context,
                f,
              ),
              selected: selected == f,
              palette: palette,
              onTap: () => onSelect(f),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 260.ms);
  }
}

class _ActiveDatePill extends StatelessWidget {
  const _ActiveDatePill({
    required this.palette,
    required this.label,
    required this.onClear,
  });

  final _Palette palette;
  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          decoration: BoxDecoration(
            color: palette.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 13,
                color: palette.primary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: palette.primary,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: palette.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final _Palette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? palette.primary : palette.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? palette.primary : palette.border,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: palette.primary.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.palette,
    required this.onTap,
  });

  final ExternalDeliveryTripSummary trip;
  final _Palette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = _stateOf(trip);
    final accent = palette.stateColor(state);

    final total = trip.totalStops;
    final done = trip.completedStops.clamp(0, total > 0 ? total : 0);
    final progress = total > 0 ? done / total : 0.0;

    // `trip_date` is date-only; `modified` is the closest thing to a
    // completion timestamp the summary endpoint returns.
    final stamp = DateTime.tryParse(trip.modified);
    final when = [
      AppDateFormat.dateFromString(trip.tripDate),
      if (stamp != null) AppDateFormat.time(stamp),
    ].where((s) => s.isNotEmpty).join(' • ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: palette.border),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.local_shipping_rounded,
                        size: 22,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trip.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            when,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(
                      label: _stateLabel(context, state),
                      color: accent,
                    ),
                  ],
                ),
                // Customer and delivery location only render once the backend
                // sends them; until then the card closes up around them.
                if (trip.customerName != null || trip.location != null) ...[
                  const SizedBox(height: 12),
                  if (trip.customerName != null)
                    _DetailLine(
                      palette: palette,
                      icon: Icons.person_outline_rounded,
                      text: trip.customerName!,
                    ),
                  if (trip.location != null) ...[
                    const SizedBox(height: 6),
                    _DetailLine(
                      palette: palette,
                      icon: Icons.location_on_outlined,
                      text: trip.location!,
                    ),
                  ],
                ],
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: palette.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Wrap (not Row) so a long locale string pushes the second
                    // pill onto its own line instead of overflowing the card.
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (trip.orderCount != null)
                            _MetricPill(
                              palette: palette,
                              icon: Icons.inventory_2_outlined,
                              label: '${trip.orderCount} orders',
                            ),
                          _MetricPill(
                            palette: palette,
                            icon: Icons.place_rounded,
                            label: '$total stops',
                          ),
                          _MetricPill(
                            palette: palette,
                            icon: Icons.task_alt_rounded,
                            label: '$done delivered',
                            color: done > 0 ? palette.success : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (trip.earnings != null)
                      Text(
                        _rupees(trip.earnings!),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: palette.success,
                        ),
                      ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: palette.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.palette,
    required this.icon,
    required this.text,
  });

  final _Palette palette;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: palette.textSecondary),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: palette.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.palette,
    required this.icon,
    required this.label,
    this.color,
  });

  final _Palette palette;
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? palette.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList({required this.palette});

  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
    );

    Widget skeleton(int i) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: palette.surfaceAlt,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [bar(140, 12), const SizedBox(height: 8), bar(90, 10)],
              ),
            ],
          ),
          const SizedBox(height: 16),
          bar(double.infinity, 6),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(
      duration: (1100 + i * 130).ms,
      color: palette.primary.withValues(alpha: 0.1),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(children: [skeleton(0), skeleton(1), skeleton(2)]),
    );
  }
}

/// Shown while filtered results are still being gathered across pages.
class _SearchProgress extends StatelessWidget {
  const _SearchProgress({required this.palette, this.compact = false});

  final _Palette palette;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 16 : 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: palette.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Searching more trips…',
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.palette,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final _Palette palette;
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(icon, size: 34, color: palette.primary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: palette.primary),
              child: Text(
                actionLabel!,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 260.ms);
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.palette,
    required this.error,
    required this.onRetry,
  });

  final _Palette palette;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: palette.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.error_outline_rounded,
              size: 30,
              color: palette.danger,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            error?.toString() ?? 'Something went wrong',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(
              app.t('retry'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
