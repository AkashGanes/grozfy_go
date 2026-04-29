import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../services/offline_storage_service.dart' show SyncStatus;
import '../services/offline_trip_manager.dart';
import '../services/sync_manager.dart';

/// Banner shown at the top of every screen when offline, plus a badge with
/// the count of pending sync items.
class OfflineStatusIndicator extends StatelessWidget {
  const OfflineStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final connectivity = ConnectivityService();

    return StreamBuilder<bool>(
      stream: connectivity.connectivityStream,
      initialData: connectivity.isConnected,
      builder: (context, snapshot) {
        final isConnected = snapshot.data ?? true;
        if (isConnected) return const SizedBox.shrink();
        return _OfflineBanner();
      },
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        border: Border(bottom: BorderSide(color: Colors.orange.shade300)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline — changes will sync when you reconnect',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ),
          const _PendingSyncBadge(),
        ],
      ),
    );
  }
}

class _PendingSyncBadge extends StatelessWidget {
  const _PendingSyncBadge();

  @override
  Widget build(BuildContext context) {
    final manager = OfflineTripManager();
    final pending = manager.pendingStatusUpdates + manager.pendingLocationPings;
    if (pending == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.shade700,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sync, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '$pending pending',
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin status banner shown while a sync is actively running or has just
/// errored. Hidden in the idle state.
class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = SyncManager();
    return StreamBuilder<SyncStatus>(
      stream: manager.syncStatusStream,
      builder: (context, snapshot) {
        final status = snapshot.data ?? SyncStatus.idle;
        if (status == SyncStatus.idle) return const SizedBox.shrink();

        Color bg;
        IconData icon;
        String message;
        switch (status) {
          case SyncStatus.syncing:
            bg = Colors.blue.shade600;
            icon = Icons.sync;
            message = 'Syncing pending changes…';
            break;
          case SyncStatus.error:
            bg = Colors.red.shade600;
            icon = Icons.error_outline;
            message = 'Sync hit an error — will retry';
            break;
          default:
            return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: bg,
          child: Row(
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}
