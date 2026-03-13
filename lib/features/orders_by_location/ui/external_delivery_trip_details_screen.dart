import 'dart:convert';

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

  String _displayValue(dynamic value) {
    if (value == null) return '-';
    if (value is String) return _valueOrDash(value);
    if (value is num || value is bool) return '$value';
    if (value is List || value is Map) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    return '$value';
  }

  String _labelFromKey(String key) {
    return key
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  List<MapEntry<String, dynamic>> _orderedTripFields(ExternalDeliveryTrip trip) {
    const priority = <String>[
      'name',
      'driver',
      'status',
      'docstatus',
      'trip_date',
      'total_stops',
      'completes_stops',
      'total_distancekm',
      'started_at',
      'completed_at',
    ];
    final remaining = Map<String, dynamic>.from(trip.rawFields)..remove('stops');
    final fields = <MapEntry<String, dynamic>>[];

    for (final key in priority) {
      if (remaining.containsKey(key)) {
        fields.add(MapEntry(key, remaining.remove(key)));
      }
    }
    fields.addAll(remaining.entries);
    return fields;
  }

  List<MapEntry<String, dynamic>> _orderedStopFields(ExternalDeliveryTripStop stop) {
    const priority = <String>[
      'stop',
      'external_delivery',
      'customer',
      'address',
      'mobile',
      'status',
      'delivered_at',
      'notes',
    ];
    final remaining = Map<String, dynamic>.from(stop.rawFields);
    final fields = <MapEntry<String, dynamic>>[];

    for (final key in priority) {
      if (remaining.containsKey(key)) {
        fields.add(MapEntry(key, remaining.remove(key)));
      }
    }
    fields.addAll(remaining.entries);
    return fields;
  }

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
                child: _fieldList(_orderedTripFields(trip)),
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
                          _fieldList(_orderedStopFields(stop)),
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

  Widget _fieldList(List<MapEntry<String, dynamic>> entries) {
    return Column(
      children: entries
          .map((entry) => _kv(_labelFromKey(entry.key), _displayValue(entry.value)))
          .toList(),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              key,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(color: AppTheme.nightBlue, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }
}
