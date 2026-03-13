import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../model/external_delivery.dart';
import '../repository/external_delivery_repository.dart';

class ExternalDeliveryTripDetailsScreen extends StatefulWidget {
  const ExternalDeliveryTripDetailsScreen({super.key, required this.tripName});

  final String tripName;

  @override
  State<ExternalDeliveryTripDetailsScreen> createState() =>
      _ExternalDeliveryTripDetailsScreenState();
}

class _ExternalDeliveryTripDetailsScreenState
    extends State<ExternalDeliveryTripDetailsScreen> {
  late Future<ExternalDeliveryTrip> _future;

  @override
  void initState() {
    super.initState();
    _future = ExternalDeliveryRepository().fetchTripDetails(widget.tripName);
  }

  String _valueOrDash(String value) => value.trim().isEmpty ? '-' : value;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'External Delivery Trip',
      subtitle: widget.tripName,
      child: FutureBuilder<ExternalDeliveryTrip>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.oceanBlue),
              ),
            );
          }

          if (snapshot.hasError) {
            return FrostCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 42,
                    color: AppTheme.mango,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    snapshot.error.toString().replaceFirst('Exception: ', ''),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _future = ExternalDeliveryRepository().fetchTripDetails(
                          widget.tripName,
                        );
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final trip = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Trip Summary'),
              FrostCard(
                child: Column(
                  children: [
                    _kv('Trip ID', trip.name),
                    _kv('Driver', trip.driver),
                    _kv('Status', trip.status),
                    _kv('Docstatus', '${trip.docstatus}'),
                    _kv('Trip Date', _valueOrDash(trip.tripDate)),
                    _kv('Total Stops', '${trip.totalStops}'),
                    _kv('Completed Stops', '${trip.completedStops}'),
                    _kv('Total Distance (km)', '${trip.totalDistanceKm}'),
                    _kv('Started At', _valueOrDash(trip.startedAt)),
                    _kv('Completed At', _valueOrDash(trip.completedAt)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const SectionLabel('Stops'),
              if (trip.stops.isEmpty)
                const FrostCard(
                  child: Text(
                    'No stops found',
                    style: TextStyle(color: Colors.black54),
                  ),
                )
              else
                ...trip.stops.map(
                  (stop) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FrostCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stop ${stop.stop}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.nightBlue,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _kv('External Delivery', stop.externalDelivery),
                          _kv('Customer', _valueOrDash(stop.customer)),
                          _kv('Address', _valueOrDash(stop.address)),
                          _kv('Mobile', _valueOrDash(stop.mobile)),
                          _kv('Status', _valueOrDash(stop.status)),
                          _kv('Delivered At', _valueOrDash(stop.deliveredAt)),
                          _kv('Notes', _valueOrDash(stop.notes)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              key,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppTheme.nightBlue),
            ),
          ),
        ],
      ),
    );
  }
}
