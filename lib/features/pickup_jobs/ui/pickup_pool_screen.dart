import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _future = _loadPool();
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

  Future<List<PickupJob>> _loadPool() =>
      PickupJobRepository().fetchPool();

  Future<void> _silentRefresh() async {
    if (!ConnectivityService().isConnected || !mounted) return;
    try {
      final jobs = await PickupJobRepository().fetchPool();
      if (mounted) setState(() { _future = Future.value(jobs); });
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
        // Refresh pool to remove the claimed job
        setState(() { _future = _loadPool(); });
        return;
      }

      // Success — navigate to pickup job detail (Mark Picked Up flow)
      setState(() { _future = _loadPool(); });
      if (mounted) {
        Navigator.of(context).pushNamed(
          AppRoutes.pickupJobDetail,
          arguments: job.name,
        );
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
    final controller = ref.read(appControllerProvider);
    final driverLat = controller.currentLatitude;
    final driverLng = controller.currentLongitude;

    return AppShell(
      title: 'Pickup Pool',
      subtitle: 'Available return pickups',
      scrollable: false,
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

          // Sort by distance if GPS available; otherwise by creation desc
          final sorted = List<PickupJob>.from(jobs);
          if (driverLat != null && driverLng != null) {
            sorted.sort((a, b) {
              final da = _distanceKm(
                  a.pickupLatitude, a.pickupLongitude, driverLat, driverLng);
              final db = _distanceKm(
                  b.pickupLatitude, b.pickupLongitude, driverLat, driverLng);
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
              await next;
            },
            child: ListView.builder(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: sorted.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _JobCard(
                  job: sorted[index],
                  distanceLabel: _distanceLabel(_distanceKm(
                    sorted[index].pickupLatitude,
                    sorted[index].pickupLongitude,
                    driverLat,
                    driverLng,
                  )),
                  isAccepting: _acceptingJobs.contains(sorted[index].name),
                  onAccept: () => _acceptJob(sorted[index]),
                  onDetail: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PickupJobDetailScreen(pickupJobName: sorted[index].name),
                    ),
                  ),
                ).animate().fadeIn(
                  delay: Duration(milliseconds: index * 40),
                  duration: 200.ms,
                ),
              ),
            ),
          );
        },
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

  @override
  Widget build(BuildContext context) {
    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.oceanBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  job.name,
                  style: const TextStyle(
                    color: AppTheme.oceanBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (distanceLabel.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.near_me_outlined,
                        size: 13, color: Colors.black38),
                    const SizedBox(width: 3),
                    Text(
                      distanceLabel,
                      style: const TextStyle(
                          color: Colors.black45, fontSize: 12),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Customer
          _infoRow(Icons.person_outline, job.customerName),
          const SizedBox(height: 5),

          // Phone (tap-to-call)
          if (job.customerMobile.isNotEmpty) ...[
            _callRow(context, job.customerMobile),
            const SizedBox(height: 5),
          ],

          // Pickup address
          _infoRow(Icons.my_location_outlined, job.pickupAddress,
              label: 'Pickup'),
          const SizedBox(height: 5),

          // Store / drop address
          _infoRow(Icons.store_outlined, job.dropAddress, label: 'Store'),

          // Scheduled window
          if (job.scheduledWindow != null &&
              job.scheduledWindow!.isNotEmpty) ...[
            const SizedBox(height: 5),
            _infoRow(Icons.schedule_outlined, job.scheduledWindow!),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 10),

          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDetail,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    side:
                        BorderSide(color: Colors.black.withValues(alpha: 0.15)),
                  ),
                  child: const Text(
                    'Details',
                    style: TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.oceanBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isAccepting ? null : onAccept,
                  icon: isAccepting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(
                    isAccepting ? 'Claiming…' : 'Accept',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, {String? label}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: Colors.black38),
        ),
        const SizedBox(width: 7),
        if (label != null) ...[
          Text(
            '$label: ',
            style: const TextStyle(
                color: Colors.black38, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
        Expanded(
          child: Text(
            text,
            style:
                const TextStyle(color: AppTheme.nightBlue, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _callRow(BuildContext context, String phone) {
    return Row(
      children: [
        const Icon(Icons.phone_outlined, size: 14, color: Colors.black38),
        const SizedBox(width: 7),
        Expanded(
          child: Text(phone,
              style: const TextStyle(
                  color: AppTheme.nightBlue, fontSize: 13)),
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
              color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call_rounded,
                    size: 12, color: Color(0xFF2E7D32)),
                SizedBox(width: 3),
                Text('Call',
                    style: TextStyle(
                        color: Color(0xFF2E7D32),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
