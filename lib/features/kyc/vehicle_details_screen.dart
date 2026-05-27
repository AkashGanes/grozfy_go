import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/utils/formatters.dart';
import '../../core/state/app_scope.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/skeleton_loader.dart';
import 'widgets/kyc_form_widgets.dart';

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
  final TextEditingController _insuranceCompanyCtrl = TextEditingController();
  final TextEditingController _policyNoCtrl = TextEditingController();
  final TextEditingController _startDateCtrl = TextEditingController();
  final TextEditingController _endDateCtrl = TextEditingController();
  final TextEditingController _carbonCheckDateCtrl = TextEditingController();
  final TextEditingController _colorCtrl = TextEditingController();
  final TextEditingController _wheelsCtrl = TextEditingController();
  final TextEditingController _doorsCtrl = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  String? _selectedFuel;
  String? _selectedUom;
  String? _selectedEmployee;
  List<String> _employeeOptions = <String>[];
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
    final dynamic args = ModalRoute.of(context)?.settings.arguments;
    final bool forceEdit =
        args is Map<String, dynamic> && args['force_edit'] == true;

    final Map<String, dynamic>? cached = app.submittedVehicleRaw;
    if (!forceEdit && cached != null && cached.isNotEmpty && mounted) {
      _initialized = true;
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.vehicleSubmittedDetails,
        arguments: cached,
      );
      return;
    }

    if (app.loggedProfileDetails?.driver == null) {
      await app.fetchLoggedInEmployeeDriverProfile();
    }
    await app.hydrateVehicleFromBackend();
    await app.fetchVehicleFormConfig();

    final List<String> uomOptions = app.uomOptions.isEmpty
        ? await app.fetchUomOptions()
        : app.uomOptions;
    final List<String> fuelOptions = app.vehicleFuelOptions;
    final List<String> employeeOptions = await app
        .fetchVehicleEmployeeOptions();

    if (!mounted || _initialized) {
      return;
    }

    final Map<String, dynamic>? submittedVehicleData = app.submittedVehicleRaw;
    if (!forceEdit &&
        submittedVehicleData != null &&
        submittedVehicleData.isNotEmpty) {
      _initialized = true;
      Future<void>.microtask(() {
        if (!mounted) {
          return;
        }
        Navigator.of(context).pushReplacementNamed(
          AppRoutes.vehicleSubmittedDetails,
          arguments: submittedVehicleData,
        );
      });
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
      _selectedEmployee = vehicle.employee;
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
    _employeeOptions = employeeOptions;
    if (_selectedEmployee == null && defaultEmployee != null) {
      _selectedEmployee = defaultEmployee;
    }
    if (_selectedEmployee != null &&
        !_employeeOptions.contains(_selectedEmployee!)) {
      _employeeOptions = <String>[_selectedEmployee!, ..._employeeOptions];
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
      controller.text = AppDateFormat.apiDate(picked);
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


  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final app = AppScope.of(context);
    setState(() => _busy = true);
    final result = await app.submitVehicleDetails(
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
      employee: _selectedEmployee ?? '',
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

    if (!result.success) {
      showInfoSnack(context, result.error ?? 'Vehicle save failed');
      return;
    }

    showInfoSnack(context, 'Vehicle is created');

    Navigator.of(context).pushNamed(
      AppRoutes.vehicleSubmittedDetails,
      arguments: result.vehicleData,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final List<String> fuelOptions = app.vehicleFuelOptions;
    final List<String> uomOptions = app.uomOptions;
    final List<String> employeeOptions = _employeeOptions.isEmpty
        ? <String>['No employees found']
        : _employeeOptions;

    final bool canSubmit = _initialized &&
        !_busy &&
        _selectedFuel != null &&
        _selectedUom != null;

    return Scaffold(
      backgroundColor: KycColors.pageBg(context),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KycHeader(
                  title: 'Vehicle Registration',
                  subtitle: 'Add all vehicle details from ERP schema',
                  assetPath: 'assets/images/scooter_vehicle.png',
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: !_initialized
                      ? _buildSkeleton()
                      : Form(
                          key: _formKey,
                          autovalidateMode:
                              AutovalidateMode.onUserInteraction,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            children: [
                              const KycSectionHeading('Required Details'),
                              KycFieldCard(
                                icon: Icons.confirmation_number_outlined,
                                label: 'License Plate',
                                child: _baseTextField(
                                  controller: _licensePlateCtrl,
                                  hint: 'Enter license plate',
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  validator: validateLicensePlate,
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.factory_outlined,
                                label: 'Make',
                                child: _baseTextField(
                                  controller: _makeCtrl,
                                  hint: 'Enter make',
                                  validator: validateVehicleName,
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.directions_car_outlined,
                                label: 'Model',
                                child: _baseTextField(
                                  controller: _modelCtrl,
                                  hint: 'Enter model',
                                  validator: validateVehicleName,
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.speed_outlined,
                                label: 'Odometer Value (Last)',
                                child: _baseTextField(
                                  controller: _odometerCtrl,
                                  hint: 'Enter odometer value',
                                  keyboardType: TextInputType.number,
                                  validator: validateOdometer,
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.local_gas_station_outlined,
                                label: 'Fuel Type',
                                trailing: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: KycColors.textHint(context),
                                ),
                                onTap: () async {
                                  final picked = await _pickFromList(
                                    title: 'Select Fuel Type',
                                    items: fuelOptions,
                                    current: _selectedFuel,
                                  );
                                  if (picked != null) {
                                    setState(() => _selectedFuel = picked);
                                  }
                                },
                                child: _staticValue(
                                  _selectedFuel,
                                  'Select fuel type',
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.straighten_outlined,
                                label: 'Fuel UOM',
                                trailing: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: KycColors.textHint(context),
                                ),
                                onTap: () async {
                                  final picked = await _pickFromList(
                                    title: 'Select Fuel UOM',
                                    items: uomOptions,
                                    current: _selectedUom,
                                  );
                                  if (picked != null) {
                                    setState(() => _selectedUom = picked);
                                  }
                                },
                                child: _staticValue(
                                  _selectedUom,
                                  'Select unit',
                                ),
                              ),
                              const SizedBox(height: 8),
                              const KycSectionHeading('Additional Details'),
                              KycFieldCard(
                                icon: Icons.calendar_month_outlined,
                                label: 'Acquisition Date',
                                trailing: Icon(
                                  Icons.calendar_today_outlined,
                                  color: KycColors.textHint(context),
                                  size: 20,
                                ),
                                onTap: () => _pickDate(_acquisitionDateCtrl),
                                child: _readonlyText(
                                  _acquisitionDateCtrl,
                                  'Select acquisition date',
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.location_on_outlined,
                                label: 'Location',
                                child: _baseTextField(
                                  controller: _locationCtrl,
                                  hint: 'Enter location',
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.pin_outlined,
                                label: 'Chassis Number',
                                child: _baseTextField(
                                  controller: _chassisNoCtrl,
                                  hint: 'Enter chassis number',
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  validator: validateChassisNumber,
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.currency_rupee_outlined,
                                label: 'Vehicle Value',
                                child: _baseTextField(
                                  controller: _vehicleValueCtrl,
                                  hint: 'Enter vehicle value',
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  validator: validateVehicleValue,
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.badge_outlined,
                                label: 'Employee',
                                trailing: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: KycColors.textHint(context),
                                ),
                                onTap: () async {
                                  final picked = await _pickFromList(
                                    title: 'Select Employee',
                                    items: employeeOptions,
                                    current: _selectedEmployee,
                                  );
                                  if (picked != null &&
                                      picked != 'No employees found') {
                                    setState(
                                        () => _selectedEmployee = picked);
                                  }
                                },
                                child: _staticValue(
                                  employeeOptions
                                          .contains(_selectedEmployee)
                                      ? _selectedEmployee
                                      : null,
                                  'Select employee',
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.shield_outlined,
                                label: 'Insurance Company',
                                child: _baseTextField(
                                  controller: _insuranceCompanyCtrl,
                                  hint: 'Enter insurance company',
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.policy_outlined,
                                label: 'Policy Number',
                                child: _baseTextField(
                                  controller: _policyNoCtrl,
                                  hint: 'Enter policy number',
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  validator: validatePolicyNumber,
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.event_available_outlined,
                                label: 'Insurance Start Date',
                                trailing: Icon(
                                  Icons.calendar_today_outlined,
                                  color: KycColors.textHint(context),
                                  size: 20,
                                ),
                                onTap: () => _pickDate(_startDateCtrl),
                                child: _readonlyText(
                                  _startDateCtrl,
                                  'Select start date',
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.event_busy_outlined,
                                label: 'Insurance End Date',
                                trailing: Icon(
                                  Icons.calendar_today_outlined,
                                  color: KycColors.textHint(context),
                                  size: 20,
                                ),
                                onTap: () => _pickDate(_endDateCtrl),
                                child: _readonlyText(
                                  _endDateCtrl,
                                  'Select end date',
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.eco_outlined,
                                label: 'Last Carbon Check Date',
                                trailing: Icon(
                                  Icons.calendar_today_outlined,
                                  color: KycColors.textHint(context),
                                  size: 20,
                                ),
                                onTap: () => _pickDate(_carbonCheckDateCtrl),
                                child: _readonlyText(
                                  _carbonCheckDateCtrl,
                                  'Select last carbon check date',
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.palette_outlined,
                                label: 'Color',
                                child: _baseTextField(
                                  controller: _colorCtrl,
                                  hint: 'Enter vehicle color',
                                  validator: validateColor,
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: KycFieldCard(
                                      icon: Icons.tire_repair_outlined,
                                      label: 'Wheels',
                                      child: _baseTextField(
                                        controller: _wheelsCtrl,
                                        hint: 'e.g. 2',
                                        keyboardType: TextInputType.number,
                                        validator: validatePositiveInt,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: KycFieldCard(
                                      icon: Icons.sensor_door_outlined,
                                      label: 'Doors',
                                      child: _baseTextField(
                                        controller: _doorsCtrl,
                                        hint: 'e.g. 0',
                                        keyboardType: TextInputType.number,
                                        validator: validatePositiveInt,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                ),
                KycPrimaryButton(
                  label: 'Submit Vehicle Details',
                  onPressed: canSubmit ? _submit : null,
                ),
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black26,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(kKycAccent),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: List.generate(8, (_) => const SkeletonFormField()),
    );
  }

  Widget _baseTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      style: kycInputStyle(context),
      decoration: kycHintDecoration(hint, hintColor: KycColors.textHint(context)),
    );
  }

  Widget _readonlyText(TextEditingController controller, String hint) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      enableInteractiveSelection: false,
      style: kycInputStyle(context),
      decoration: kycHintDecoration(hint, hintColor: KycColors.textHint(context)),
    );
  }

  Widget _staticValue(String? value, String hint) {
    final hasValue = value != null && value.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        hasValue ? value : hint,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
          color: hasValue ? KycColors.textPrimary(context) : KycColors.textHint(context),
        ),
      ),
    );
  }

  Future<String?> _pickFromList({
    required String title,
    required List<String> items,
    String? current,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KycColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return _ListPickerSheet(
          title: title,
          items: items,
          current: current,
        );
      },
    );
  }
}

class _ListPickerSheet extends StatefulWidget {
  const _ListPickerSheet({
    required this.title,
    required this.items,
    required this.current,
  });

  final String title;
  final List<String> items;
  final String? current;

  @override
  State<_ListPickerSheet> createState() => _ListPickerSheetState();
}

class _ListPickerSheetState extends State<_ListPickerSheet> {
  late final TextEditingController _queryCtrl;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _queryCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  List<String> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return widget.items
        .where((item) => item.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.82,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KycColors.sheetGrabber(context),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: KycColors.textPrimary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: KycSearchInput(
                  controller: _queryCtrl,
                  hint: 'Search '
                      '${widget.title.replaceAll(RegExp(r'^Select\s+'), '').toLowerCase()}',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (results.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: KycColors.accentSoft(context),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.search_off_rounded,
                          color: kKycAccent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No matching options',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: KycColors.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${results.length} ${results.length == 1 ? 'result' : 'results'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: KycColors.textSecondary(context),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final item = results[i];
                      return KycResultTile(
                        label: item,
                        selected: item == widget.current,
                        onTap: () => Navigator.of(context).pop(item),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
