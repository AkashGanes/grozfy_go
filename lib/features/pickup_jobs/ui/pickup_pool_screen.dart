import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/navigation/app_routes.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/state/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/context_colors.dart';
import '../../../core/widgets/app_shell.dart';
import '../../kyc/widgets/kyc_form_widgets.dart';
import '../model/pickup_job.dart';
import '../repository/pickup_job_repository.dart';
import 'pickup_job_detail_screen.dart';

class PickupPoolScreen extends ConsumerStatefulWidget {
  const PickupPoolScreen({super.key});

  @override
  ConsumerState<PickupPoolScreen> createState() => _PickupPoolScreenState();
}

class _PickupPoolScreenState extends ConsumerState<PickupPoolScreen> {
  late Future<List<PickupJob>> _future;
  final Set<String> _acceptingJobs = {};
  Timer? _pollTimer;
  int _consecutiveFailures = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _future = _loadPool();
    _schedulePoll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _schedulePoll() {
    final seconds = _consecutiveFailures == 0
        ? 30
        : (30 * (1 << _consecutiveFailures)).clamp(30, 300);
    _pollTimer = Timer(Duration(seconds: seconds), () async {
      await _silentRefresh();
      if (mounted) _schedulePoll();
    });
  }

  Future<List<PickupJob>> _loadPool() => PickupJobRepository().fetchPool();

  Future<void> _silentRefresh() async {
    if (!ConnectivityService().isConnected || !mounted) return;
    try {
      final pool = await PickupJobRepository().fetchPool();
      if (!mounted) return;
      _consecutiveFailures = 0;
      setState(() {
        _future = Future.value(pool);
      });
    } catch (_) {
      _consecutiveFailures++;
    }
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  List<PickupJob> _filteredJobs(List<PickupJob> jobs) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return jobs;
    return jobs.where((job) {
      return job.name.toLowerCase().contains(q) ||
          job.customerName.toLowerCase().contains(q) ||
          job.customerMobile.toLowerCase().contains(q) ||
          job.pickupAddress.toLowerCase().contains(q) ||
          job.dropAddress.toLowerCase().contains(q);
    }).toList();
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: KycSearchInput(
        controller: _searchController,
        hint: 'Search by name, customer, address…',
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  // ── Haversine distance ─────────────────────────────────────────────────────

  double? _distanceKm(
      double? jobLat, double? jobLng, double? dLat, double? dLng) {
    if (jobLat == null || jobLng == null || dLat == null || dLng == null) {
      return null;
    }
    const r = 6371.0;
    final dlat = _deg2rad(jobLat - dLat);
    final dlon = _deg2rad(jobLng - dLng);
    final a = math.sin(dlat / 2) * math.sin(dlat / 2) +
        math.cos(_deg2rad(dLat)) *
            math.cos(_deg2rad(jobLat)) *
            math.sin(dlon / 2) *
            math.sin(dlon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _deg2rad(double deg) => deg * math.pi / 180;

  String _distanceLabel(double? km) {
    if (km == null) return '';
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  // ── Accept ─────────────────────────────────────────────────────────────────

  Future<void> _acceptJob(PickupJob job) async {
    if (_acceptingJobs.contains(job.name)) return;
    setState(() => _acceptingJobs.add(job.name));
    try {
      final result = await PickupJobRepository().acceptJob(job.name);
      if (!mounted) return;

      if (!result.success) {
        final error = result.error ?? '';
        if (error.contains('already_claimed_by_another_driver')) {
          showInfoSnack(context, 'Someone else got it first');
        } else {
          showInfoSnack(context, error.isNotEmpty ? error : 'Could not accept job');
        }
        setState(() { _future = _loadPool(); });
        return;
      }

      await PickupJobRepository().saveActiveJob(job.name);
      if (result.deliveryTrip.isNotEmpty) {
        await PickupJobRepository().saveActiveTrip(result.deliveryTrip);
      }
      setState(() { _future = _loadPool(); });
      if (mounted) {
        Navigator.of(context)
            .pushNamed(AppRoutes.pickupJobDetail, arguments: job.name);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.toLowerCase().contains('already_claimed') ||
          msg.toLowerCase().contains('already claimed')) {
        showInfoSnack(context, 'Someone else got it first');
        setState(() { _future = _loadPool(); });
      } else {
        showInfoSnack(context, msg.isNotEmpty ? msg : 'Could not accept job');
      }
    } finally {
      if (mounted) setState(() => _acceptingJobs.remove(job.name));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final driverLat = controller.currentLatitude;
    final driverLng = controller.currentLongitude;

    return AppShell(
      title: 'Pickup Pool',
      subtitle: 'Available return pickups',
      scrollable: false,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: FutureBuilder<List<PickupJob>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return _loadingView();
                }
                if (snapshot.hasError) {
                  return _errorView(
                    snapshot.error.toString().replaceFirst('Exception: ', ''),
                  );
                }
                final jobs = snapshot.data ?? [];
                if (jobs.isEmpty) return _emptyView();

                final sorted = List<PickupJob>.from(jobs);
                if (driverLat != null && driverLng != null) {
                  sorted.sort((a, b) {
                    final da = _distanceKm(a.pickupLatitude, a.pickupLongitude,
                        driverLat, driverLng);
                    final db = _distanceKm(b.pickupLatitude, b.pickupLongitude,
                        driverLat, driverLng);
                    if (da == null && db == null) return 0;
                    if (da == null) return 1;
                    if (db == null) return -1;
                    return da.compareTo(db);
                  });
                } else {
                  sorted.sort((a, b) => b.creation.compareTo(a.creation));
                }

                final displayed = _filteredJobs(sorted);

                if (_searchQuery.trim().isNotEmpty && displayed.isEmpty) {
                  return _searchEmptyView();
                }

                return RefreshIndicator(
                  color: context.scheme.primary,
                  onRefresh: () async {
                    final next = _loadPool();
                    setState(() { _future = next; });
                    await next;
                  },
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    itemCount: displayed.length,
                    itemBuilder: (context, index) => _JobCard(
                      job: displayed[index],
                      distanceLabel: _distanceLabel(_distanceKm(
                        displayed[index].pickupLatitude,
                        displayed[index].pickupLongitude,
                        driverLat,
                        driverLng,
                      )),
                      isAccepting:
                          _acceptingJobs.contains(displayed[index].name),
                      onAccept: () => _acceptJob(displayed[index]),
                      onDetail: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PickupJobDetailScreen(
                              pickupJobName: displayed[index].name),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingView() => Center(
        child: CircularProgressIndicator(color: context.scheme.primary),
      );

  Widget _errorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FrostCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 40, color: AppTheme.mango),
              const SizedBox(height: 10),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textSecondary)),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () => setState(() { _future = _loadPool(); }),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchEmptyView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 48, color: context.iconMuted),
              const SizedBox(height: 16),
              Text(
                'No pickups match your search',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              Text(
                'Try a different name, phone, or address',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textTertiary, fontSize: 13),
              ),
            ],
          ),
        ),
      );

  Widget _emptyView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 56, color: context.iconMuted),
              const SizedBox(height: 16),
              Text(
                'No pickups available right now',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              Text(
                'Pull down to refresh',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textTertiary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
}

// ── Job card ──────────────────────────────────────────────────────────────────

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.distanceLabel,
    required this.isAccepting,
    required this.onAccept,
    required this.onDetail,
  });

  final PickupJob job;
  final String distanceLabel;
  final bool isAccepting;
  final VoidCallback onAccept;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    final Color cardBg = context.cardColor;
    final Color cardBorder = context.borderSubtle;
    final Color textPrimary = context.textPrimary;
    final Color textSecondary = context.textSecondary;
    final Color accent = context.scheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                border: Border.all(color: cardBorder, width: 1),
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
                    padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header row
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                job.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                            if (distanceLabel.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: accent.withValues(alpha: 0.2)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.near_me_outlined,
                                        size: 11, color: accent),
                                    const SizedBox(width: 3),
                                    Text(
                                      distanceLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _MetaRow(
                          icon: Icons.person_rounded,
                          iconColor: context.success,
                          iconBg: context.successContainer,
                          label: 'Customer',
                          value: job.customerName,
                          labelColor: textSecondary,
                          valueColor: textPrimary,
                        ),
                        if (job.customerMobile.isNotEmpty)
                          _PhoneRow(
                            phone: job.customerMobile,
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                        _MetaRow(
                          icon: Icons.my_location_outlined,
                          iconColor: const Color(0xFF7C3AED),
                          iconBg: context.isDark
                              ? const Color(0xFF2D2148)
                              : const Color(0xFFEFE9FE),
                          label: 'Pickup',
                          value: job.pickupAddress,
                          labelColor: textSecondary,
                          valueColor: textPrimary,
                        ),
                        _MetaRow(
                          icon: Icons.store_rounded,
                          iconColor: const Color(0xFFF38B19),
                          iconBg: context.isDark
                              ? const Color(0xFF3A2613)
                              : const Color(0xFFFFEFDA),
                          label: 'Store',
                          value: job.dropAddress,
                          labelColor: textSecondary,
                          valueColor: textPrimary,
                        ),
                        if (job.scheduledWindow != null &&
                            job.scheduledWindow!.isNotEmpty)
                          _MetaRow(
                            icon: Icons.schedule_outlined,
                            iconColor: const Color(0xFF0891B2),
                            iconBg: context.isDark
                                ? const Color(0xFF0C2A30)
                                : const Color(0xFFE0F2F7),
                            label: 'Schedule',
                            value: job.scheduledWindow!,
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                      ],
                    ),
                  ),
                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onDetail,
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              side: BorderSide(color: cardBorder),
                            ),
                            child: Text(
                              'Details',
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  accent.withValues(alpha: 0.5),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: isAccepting ? null : onAccept,
                            icon: isAccepting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(
                                    Icons.check_circle_outline_rounded,
                                    size: 16),
                            label: Text(
                              isAccepting ? 'Claiming…' : 'Accept',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Left accent bar
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: IgnorePointer(child: ColoredBox(color: accent)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Meta row ──────────────────────────────────────────────────────────────────

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
            width: 72,
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: valueColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Phone row with tap-to-call ────────────────────────────────────────────────

class _PhoneRow extends StatelessWidget {
  const _PhoneRow({
    required this.phone,
    required this.labelColor,
    required this.valueColor,
  });

  final String phone;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final iconBg = context.infoContainer;
    final iconColor = context.info;

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
            child: Icon(Icons.phone_outlined, size: 14, color: iconColor),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Text(
              'Phone',
              style: TextStyle(
                fontSize: 12.5,
                color: labelColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              phone,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: valueColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              final uri = Uri(scheme: 'tel', path: phone);
              // ignore: deprecated_member_use
              if (await canLaunchUrl(uri)) await launchUrl(uri);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: context.successContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: context.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.call_rounded,
                      size: 12, color: context.success),
                  const SizedBox(width: 3),
                  Text(
                    'Call',
                    style: TextStyle(
                      color: context.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
