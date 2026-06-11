import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_routes.dart';
import '../../../core/services/connectivity_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/state/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
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
  PickupJob? _activePickupJob;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _future = _loadPool();
    _loadActiveJob();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _silentRefresh(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<List<PickupJob>> _loadPool() => PickupJobRepository().fetchPool();

  Future<void> _loadActiveJob() async {
    final job = await PickupJobRepository().loadActivePickupJob();
    if (mounted) setState(() => _activePickupJob = job);
  }

  Future<void> _silentRefresh() async {
    if (!ConnectivityService().isConnected || !mounted) return;
    try {
      final results = await Future.wait([
        PickupJobRepository().fetchPool(),
        PickupJobRepository().loadActivePickupJob(),
      ]);
      if (!mounted) return;
      setState(() {
        _future = Future.value(results[0] as List<PickupJob>);
        _activePickupJob = results[1] as PickupJob?;
      });
    } catch (_) {}
  }

  // ── Haversine distance in km ───────────────────────────────────────────────

  double? _distanceKm(
      double? jobLat, double? jobLng, double? driverLat, double? driverLng) {
    if (jobLat == null ||
        jobLng == null ||
        driverLat == null ||
        driverLng == null) { return null; }
    const r = 6371.0;
    final dLat = _deg2rad(jobLat - driverLat);
    final dLon = _deg2rad(jobLng - driverLng);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(driverLat)) *
            math.cos(_deg2rad(jobLat)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _deg2rad(double deg) => deg * math.pi / 180;

  String _distanceLabel(double? km) {
    if (km == null) return '';
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  // ── Accept flow (B.2) ─────────────────────────────────────────────────────

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

      // Save job + trip name so the detail screen can load the trip stop.
      await PickupJobRepository().saveActiveJob(job.name);
      if (result.deliveryTrip.isNotEmpty) {
        await PickupJobRepository().saveActiveTrip(result.deliveryTrip);
      }
      setState(() { _future = _loadPool(); });
      if (mounted) {
        Navigator.of(context)
            .pushNamed(AppRoutes.pickupJobDetail, arguments: job.name)
            .then((_) => _loadActiveJob());
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final driverLat = controller.currentLatitude;
    final driverLng = controller.currentLongitude;

    final hasActiveDelivery = controller.activeOrder != null;
    final hasActivePickup = _activePickupJob != null;
    final isBlocked = hasActiveDelivery || hasActivePickup;

    return AppShell(
      title: 'Pickup Pool',
      subtitle: 'Available return pickups',
      scrollable: false,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (isBlocked)
            _PoolBlockBanner(
              isDeliveryOrder: hasActiveDelivery,
              activePickupJobName:
                  hasActivePickup ? _activePickupJob!.name : null,
              onViewTap: () {
                if (hasActiveDelivery) {
                  Navigator.of(context).pushNamed(AppRoutes.orderStatus);
                } else {
                  Navigator.of(context)
                      .pushNamed(
                        AppRoutes.pickupJobDetail,
                        arguments: _activePickupJob!.name,
                      )
                      .then((_) => _loadActiveJob());
                }
              },
            ),
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

                return RefreshIndicator(
                  color: AppTheme.oceanBlue,
                  onRefresh: () async {
                    final next = _loadPool();
                    setState(() { _future = next; });
                    await Future.wait([next, _loadActiveJob()]);
                  },
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    itemCount: sorted.length,
                    itemBuilder: (context, index) => _JobCard(
                        job: sorted[index],
                        distanceLabel: _distanceLabel(_distanceKm(
                          sorted[index].pickupLatitude,
                          sorted[index].pickupLongitude,
                          driverLat,
                          driverLng,
                        )),
                        isAccepting:
                            _acceptingJobs.contains(sorted[index].name),
                        onAccept: () => _acceptJob(sorted[index]),
                        onDetail: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PickupJobDetailScreen(
                                pickupJobName: sorted[index].name),
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

  Widget _loadingView() => const Center(
        child: CircularProgressIndicator(color: AppTheme.oceanBlue),
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
                  style: const TextStyle(color: Colors.black54)),
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

  Widget _emptyView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 56, color: Colors.black.withValues(alpha: 0.15)),
              const SizedBox(height: 16),
              const Text(
                'No pickups available right now',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black45,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Pull down to refresh',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black26, fontSize: 13),
              ),
            ],
          ),
        ),
      );
}

// ── Blocking banner ───────────────────────────────────────────────────────────

class _PoolBlockBanner extends StatelessWidget {
  const _PoolBlockBanner({
    required this.isDeliveryOrder,
    required this.activePickupJobName,
    required this.onViewTap,
  });

  final bool isDeliveryOrder;
  final String? activePickupJobName;
  final VoidCallback onViewTap;

  @override
  Widget build(BuildContext context) {
    final message = isDeliveryOrder
        ? 'Active delivery order in progress — finish it before claiming a pickup.'
        : 'Pickup job in progress — complete it before claiming another.';
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.mango.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.mango.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppTheme.mango, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppTheme.mango,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onViewTap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'View →',
              style: TextStyle(
                color: AppTheme.mango,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pool card ─────────────────────────────────────────────────────────────────

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

  static const Color _accent = Color(0xFFF38B19);

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark ? const Color(0xFF1B1E2A) : Colors.white;
    final Color cardBorder =
        isDark ? const Color(0xFF2A2F3D) : const Color(0xFFE4E7EC);
    final Color textPrimary =
        isDark ? const Color(0xFFF2F4F7) : const Color(0xFF101828);
    final Color textSecondary =
        isDark ? const Color(0xFFA4ABB8) : const Color(0xFF667085);

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
                border: Border.all(color: cardBorder),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
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
                        // Job name + distance chip
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
                                  color: _accent.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(
                                      color: _accent.withValues(alpha: 0.35)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.near_me_rounded,
                                        size: 11,
                                        color: _accent),
                                    const SizedBox(width: 4),
                                    Text(
                                      distanceLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: _accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Customer
                        _MetaRow(
                          icon: Icons.person_rounded,
                          iconColor: const Color(0xFF1AB36A),
                          iconBg: isDark
                              ? const Color(0xFF14352A)
                              : const Color(0xFFE7F7EE),
                          label: 'Customer',
                          value: job.customerName,
                          labelColor: textSecondary,
                          valueColor: textPrimary,
                        ),
                        // Phone
                        if (job.customerMobile.isNotEmpty)
                          _PhoneRow(
                            phone: job.customerMobile,
                            iconBg: isDark
                                ? const Color(0xFF1A2C4F)
                                : const Color(0xFFE5EEFB),
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                        // Pickup address
                        _MetaRow(
                          icon: Icons.my_location_rounded,
                          iconColor: const Color(0xFFF38B19),
                          iconBg: isDark
                              ? const Color(0xFF3A2613)
                              : const Color(0xFFFFEFDA),
                          label: 'Pickup',
                          value: job.pickupAddress,
                          labelColor: textSecondary,
                          valueColor: textPrimary,
                        ),
                        // Store / drop
                        _MetaRow(
                          icon: Icons.store_rounded,
                          iconColor: const Color(0xFF2D6CDF),
                          iconBg: isDark
                              ? const Color(0xFF1A2C4F)
                              : const Color(0xFFE5EEFB),
                          label: 'Store',
                          value: job.dropAddress,
                          labelColor: textSecondary,
                          valueColor: textPrimary,
                        ),
                        // Scheduled window
                        if (job.scheduledWindow != null &&
                            job.scheduledWindow!.isNotEmpty)
                          _MetaRow(
                            icon: Icons.schedule_rounded,
                            iconColor: const Color(0xFF7C3AED),
                            iconBg: isDark
                                ? const Color(0xFF2D2148)
                                : const Color(0xFFEFE9FE),
                            label: 'Window',
                            value: job.scheduledWindow!,
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                        // Amount
                        if (job.amount != null && job.amount! > 0)
                          _MetaRow(
                            icon: Icons.currency_rupee_rounded,
                            iconColor: const Color(0xFF1AB36A),
                            iconBg: isDark
                                ? const Color(0xFF14352A)
                                : const Color(0xFFE7F7EE),
                            label: 'Amount',
                            value: 'Rs. ${job.amount!.toStringAsFixed(0)}',
                            labelColor: textSecondary,
                            valueColor: textPrimary,
                          ),
                      ],
                    ),
                  ),
                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: isDark
                                ? const Color(0xFF2A2F3D)
                                : const Color(0xFFF2F4F7),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: onDetail,
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                height: 48,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.info_outline_rounded,
                                        size: 16, color: textSecondary),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Details',
                                      style: TextStyle(
                                        color: textSecondary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: Material(
                            color: isAccepting
                                ? const Color(0xFF1F5FE8).withValues(alpha: 0.6)
                                : const Color(0xFF1F5FE8),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: isAccepting ? null : onAccept,
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                height: 48,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (isAccepting)
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    else
                                      const Icon(
                                          Icons.check_circle_outline_rounded,
                                          size: 16,
                                          color: Colors.white),
                                    const SizedBox(width: 6),
                                    Text(
                                      isAccepting ? 'Claiming…' : 'Accept Job',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
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
                ],
              ),
            ),
            // Left accent bar
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: IgnorePointer(
                child: ColoredBox(color: _accent),
              ),
            ),
          ],
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

class _PhoneRow extends StatelessWidget {
  const _PhoneRow({
    required this.phone,
    required this.iconBg,
    required this.labelColor,
    required this.valueColor,
  });

  final String phone;
  final Color iconBg;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.phone_rounded, size: 14,
                color: Color(0xFF2D6CDF)),
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
                fontWeight: FontWeight.w700,
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
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.35)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.call_rounded, size: 12, color: Color(0xFF2E7D32)),
                  SizedBox(width: 4),
                  Text(
                    'Call',
                    style: TextStyle(
                      color: Color(0xFF2E7D32),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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
