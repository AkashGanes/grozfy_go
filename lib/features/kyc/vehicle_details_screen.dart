import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';

class VehicleDetailsScreen extends StatefulWidget {
  const VehicleDetailsScreen({super.key});

  @override
  State<VehicleDetailsScreen> createState() => _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends State<VehicleDetailsScreen> {
  VehicleType _selectedType = VehicleType.bike;
  final TextEditingController _vehicleNumberCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _vehicleNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _uploadRc() async {
    final app = AppScope.of(context);
    setState(() => _busy = true);
    await app.uploadRcDocument();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    showInfoSnack(context, 'RC document uploaded successfully');
  }

  void _submit() {
    final app = AppScope.of(context);
    final String? error = app.submitVehicleDetails(
      type: _selectedType,
      vehicleNumber: _vehicleNumberCtrl.text,
    );

    if (error != null) {
      showInfoSnack(context, error);
      return;
    }

    showInfoSnack(context, 'Vehicle submitted for verification');
    Navigator.of(context).pushNamed(AppRoutes.bankSetup);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return AppShell(
      title: 'Vehicle Registration',
      subtitle: 'Add delivery vehicle details and RC proof',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
            child: Column(
              children: [
                DropdownButtonFormField<VehicleType>(
                  initialValue: _selectedType,
                  items: VehicleType.values
                      .map(
                        (VehicleType type) => DropdownMenuItem<VehicleType>(
                          value: type,
                          child: Text(type.label),
                        ),
                      )
                      .toList(),
                  onChanged: (VehicleType? value) {
                    if (value != null) {
                      setState(() => _selectedType = value);
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Type',
                    prefixIcon: Icon(Icons.two_wheeler_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _vehicleNumberCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Number',
                    prefixIcon: Icon(Icons.confirmation_number_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        app.rcUploaded
                            ? 'RC document uploaded'
                            : 'Upload RC document',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _uploadRc,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Upload'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: const Text('Submit Vehicle Details'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
