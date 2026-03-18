import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';

class VehicleDetailsScreen extends StatefulWidget {
  const VehicleDetailsScreen({super.key});

  @override
  State<VehicleDetailsScreen> createState() => _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends State<VehicleDetailsScreen> {
  final TextEditingController _licensePlateCtrl = TextEditingController();
  final TextEditingController _makeCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();
  final TextEditingController _odometerCtrl = TextEditingController();
  final TextEditingController _acquisitionDateCtrl = TextEditingController();
  final TextEditingController _locationCtrl = TextEditingController();
  final TextEditingController _chassisNoCtrl = TextEditingController();
  final TextEditingController _vehicleValueCtrl = TextEditingController();
  final TextEditingController _employeeCtrl = TextEditingController();
  final TextEditingController _insuranceCompanyCtrl = TextEditingController();
  final TextEditingController _policyNoCtrl = TextEditingController();
  final TextEditingController _startDateCtrl = TextEditingController();
  final TextEditingController _endDateCtrl = TextEditingController();
  final TextEditingController _carbonCheckDateCtrl = TextEditingController();
  final TextEditingController _colorCtrl = TextEditingController();
  final TextEditingController _wheelsCtrl = TextEditingController();
  final TextEditingController _doorsCtrl = TextEditingController();

  String? _selectedFuel;
  String? _selectedUom;
  bool _busy = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapForm();
    });
  }

  @override
  void dispose() {
    _licensePlateCtrl.dispose();
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _odometerCtrl.dispose();
    _acquisitionDateCtrl.dispose();
    _locationCtrl.dispose();
    _chassisNoCtrl.dispose();
    _vehicleValueCtrl.dispose();
    _employeeCtrl.dispose();
    _insuranceCompanyCtrl.dispose();
    _policyNoCtrl.dispose();
    _startDateCtrl.dispose();
    _endDateCtrl.dispose();
    _carbonCheckDateCtrl.dispose();
    _colorCtrl.dispose();
    _wheelsCtrl.dispose();
    _doorsCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrapForm() async {
    final app = AppScope.of(context);
    if (app.loggedProfileDetails?.driver == null) {
      await app.fetchLoggedInEmployeeDriverProfile();
    }
    await app.fetchVehicleFormConfig();

    final List<String> uomOptions = app.uomOptions.isEmpty
        ? await app.fetchUomOptions()
        : app.uomOptions;
    final List<String> fuelOptions = app.vehicleFuelOptions;

    if (!mounted || _initialized) {
      return;
    }

    final vehicle = app.vehicle;
    if (vehicle != null) {
      _licensePlateCtrl.text = vehicle.licensePlate;
      _makeCtrl.text = vehicle.make;
      _modelCtrl.text = vehicle.model;
      _odometerCtrl.text = vehicle.lastOdometer.toString();
      _acquisitionDateCtrl.text = vehicle.acquisitionDate ?? '';
      _locationCtrl.text = vehicle.location ?? '';
      _chassisNoCtrl.text = vehicle.chassisNo ?? '';
      _vehicleValueCtrl.text = vehicle.vehicleValue?.toString() ?? '';
      _employeeCtrl.text = vehicle.employee ?? '';
      _insuranceCompanyCtrl.text = vehicle.insuranceCompany ?? '';
      _policyNoCtrl.text = vehicle.policyNo ?? '';
      _startDateCtrl.text = vehicle.startDate ?? '';
      _endDateCtrl.text = vehicle.endDate ?? '';
      _carbonCheckDateCtrl.text = vehicle.carbonCheckDate ?? '';
      _colorCtrl.text = vehicle.color ?? '';
      _wheelsCtrl.text = vehicle.wheels?.toString() ?? '';
      _doorsCtrl.text = vehicle.doors?.toString() ?? '';
      _selectedFuel = vehicle.fuelType;
      _selectedUom = vehicle.uom;
    }

    final String? defaultEmployee = app.loggedProfileDetails?.driver == null
        ? null
        : app.loggedProfileDetails!.driver!['employee']?.toString();
    if (_employeeCtrl.text.trim().isEmpty && defaultEmployee != null) {
      _employeeCtrl.text = defaultEmployee;
    }

    if (_selectedFuel == null && fuelOptions.isNotEmpty) {
      _selectedFuel = fuelOptions.first;
    }
    if (_selectedUom == null && uomOptions.isNotEmpty) {
      _selectedUom = uomOptions.contains('Litre') ? 'Litre' : uomOptions.first;
    }

    setState(() {
      _initialized = true;
    });
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final DateTime now = DateTime.now();
    final DateTime initialDate = _parseDate(controller.text) ?? now;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      controller.text = _formatDate(picked);
    });
  }

  DateTime? _parseDate(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      return DateTime.parse(trimmed);
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<void> _submit() async {
    final app = AppScope.of(context);
    setState(() => _busy = true);
    final String? error = await app.submitVehicleDetails(
      licensePlate: _licensePlateCtrl.text,
      make: _makeCtrl.text,
      model: _modelCtrl.text,
      lastOdometer: _odometerCtrl.text,
      fuelType: _selectedFuel ?? '',
      uom: _selectedUom ?? '',
      acquisitionDate: _acquisitionDateCtrl.text,
      location: _locationCtrl.text,
      chassisNo: _chassisNoCtrl.text,
      vehicleValue: _vehicleValueCtrl.text,
      employee: _employeeCtrl.text,
      insuranceCompany: _insuranceCompanyCtrl.text,
      policyNo: _policyNoCtrl.text,
      startDate: _startDateCtrl.text,
      endDate: _endDateCtrl.text,
      carbonCheckDate: _carbonCheckDateCtrl.text,
      color: _colorCtrl.text,
      wheels: _wheelsCtrl.text,
      doors: _doorsCtrl.text,
    );

    if (!mounted) {
      return;
    }
    setState(() => _busy = false);

    if (error != null) {
      showInfoSnack(context, error);
      return;
    }

    showInfoSnack(context, 'Vehicle details saved successfully');
    Navigator.of(context).pushNamed(AppRoutes.bankSetup);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final List<String> fuelOptions = app.vehicleFuelOptions;
    final List<String> uomOptions = app.uomOptions;

    return AppShell(
      title: 'Vehicle Registration',
      subtitle: 'Add all vehicle details from ERP schema',
      loading: _busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Required Details'),
          FrostCard(
            child: Column(
              children: [
                TextField(
                  controller: _licensePlateCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'License Plate *',
                    prefixIcon: Icon(Icons.confirmation_number_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _makeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Make *',
                    prefixIcon: Icon(Icons.factory_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _modelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Model *',
                    prefixIcon: Icon(Icons.directions_car_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _odometerCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Odometer Value (Last) *',
                    prefixIcon: Icon(Icons.speed_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedFuel,
                  items: fuelOptions
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) {
                    if (value != null) {
                      setState(() => _selectedFuel = value);
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Fuel Type *',
                    prefixIcon: Icon(Icons.local_gas_station_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedUom,
                  items: uomOptions
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) {
                    setState(() => _selectedUom = value);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Fuel UOM *',
                    prefixIcon: Icon(Icons.straighten_outlined),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const SectionLabel('Additional Details'),
          FrostCard(
            child: Column(
              children: [
                _dateField(
                  controller: _acquisitionDateCtrl,
                  label: 'Acquisition Date',
                  icon: Icons.calendar_month_outlined,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _locationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _chassisNoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Chassis Number',
                    prefixIcon: Icon(Icons.pin_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _vehicleValueCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Value',
                    prefixIcon: Icon(Icons.currency_rupee_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _employeeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Employee',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _insuranceCompanyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Insurance Company',
                    prefixIcon: Icon(Icons.shield_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _policyNoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Policy Number',
                    prefixIcon: Icon(Icons.policy_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                _dateField(
                  controller: _startDateCtrl,
                  label: 'Insurance Start Date',
                  icon: Icons.event_available_outlined,
                ),
                const SizedBox(height: 12),
                _dateField(
                  controller: _endDateCtrl,
                  label: 'Insurance End Date',
                  icon: Icons.event_busy_outlined,
                ),
                const SizedBox(height: 12),
                _dateField(
                  controller: _carbonCheckDateCtrl,
                  label: 'Last Carbon Check Date',
                  icon: Icons.eco_outlined,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _colorCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Color',
                    prefixIcon: Icon(Icons.palette_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _wheelsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Wheels',
                          prefixIcon: Icon(Icons.tire_repair_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _doorsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Doors',
                          prefixIcon: Icon(Icons.sensor_door_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed:
                (_busy ||
                    !_initialized ||
                    _selectedFuel == null ||
                    _selectedUom == null)
                ? null
                : _submit,
            child: const Text('Submit Vehicle Details'),
          ),
        ],
      ),
    );
  }

  Widget _dateField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: () => _pickDate(controller),
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }
}
