typedef Validator = String? Function(String?);

String? requiredField(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'This field is required';
  }
  return null;
}

/// Indian vehicle registration: TN01AB1234 (state + district + series + number).
/// Accepts with or without spaces/hyphens between groups.
String? validateLicensePlate(String? value) {
  final String? req = requiredField(value);
  if (req != null) return req;
  final String v = value!.trim().replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (!RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z]{1,3}[0-9]{4}$').hasMatch(v)) {
    return 'Enter a valid plate (e.g. TN01AB1234)';
  }
  return null;
}

/// Vehicle make/manufacturer — letters, digits, spaces, hyphens, periods. 2–50 chars.
String? validateVehicleName(String? value) {
  final String? req = requiredField(value);
  if (req != null) return req;
  final String v = value!.trim();
  if (v.length < 2 || v.length > 50) {
    return 'Must be between 2 and 50 characters';
  }
  if (!RegExp(r"^[A-Za-z0-9 \-\.]+$").hasMatch(v)) {
    return 'Only letters, digits, spaces, hyphens and periods allowed';
  }
  return null;
}

/// Chassis / VIN — 17 alphanumeric characters, no I, O, or Q.
String? validateChassisNumber(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final String v = value.trim().toUpperCase();
  if (!RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(v)) {
    return 'Chassis number must be 17 characters (no I, O, Q)';
  }
  return null;
}

/// Insurance policy number — optional, alphanumeric + hyphens/slashes, 6–30 chars.
String? validatePolicyNumber(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final String v = value.trim();
  if (v.length < 6 || v.length > 30) {
    return 'Policy number must be 6–30 characters';
  }
  if (!RegExp(r'^[A-Za-z0-9\-/]+$').hasMatch(v)) {
    return 'Only letters, digits, hyphens and slashes allowed';
  }
  return null;
}

/// Vehicle color — optional, letters and spaces only, 2–30 chars.
String? validateColor(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final String v = value.trim();
  if (v.length < 2 || v.length > 30) {
    return 'Color must be 2–30 characters';
  }
  if (!RegExp(r'^[A-Za-z ]+$').hasMatch(v)) {
    return 'Color should contain letters only';
  }
  return null;
}

String? validateOdometer(String? value) {
  final String? req = requiredField(value);
  if (req != null) return req;
  final int? parsed = int.tryParse(value!.trim());
  if (parsed == null || parsed < 0) {
    return 'Enter a valid non-negative number';
  }
  return null;
}

String? validateVehicleValue(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final double? parsed = double.tryParse(value.trim());
  if (parsed == null || parsed < 0) {
    return 'Enter a valid amount';
  }
  return null;
}

String? validatePositiveInt(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final int? parsed = int.tryParse(value.trim());
  if (parsed == null || parsed <= 0) {
    return 'Enter a valid positive number';
  }
  return null;
}

/// IFSC code: 4 uppercase letters + '0' + 6 alphanumeric = exactly 11 characters.
/// Example: SBIN0001234, HDFC0004321
String? validateBranchCode(String? value) {
  final String? req = requiredField(value);
  if (req != null) return req;
  final String v = value!.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(v)) {
    return 'Enter a valid IFSC code (e.g. SBIN0001234)';
  }
  return null;
}

String? validateIBAN(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final String v = value.replaceAll(' ', '').toUpperCase();
  if (!RegExp(r'^[A-Z0-9]{8,34}$').hasMatch(v)) {
    return 'Enter a valid IBAN (8–34 alphanumeric characters)';
  }
  return null;
}

/// Indian bank account number: digits only, 9–18 digits.
String? validateBankAccountNo(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final String v = value.trim();
  if (!RegExp(r'^\d{9,18}$').hasMatch(v)) {
    return 'Enter a valid account number (9–18 digits)';
  }
  return null;
}

/// Indian driving license: 2-letter state code + 2-digit RTO + 4-digit year + 7-digit unique number.
String? validateLicenseNumber(String? value, {bool required = false}) {
  if (value == null || value.trim().isEmpty) {
    return required ? 'License number is required' : null;
  }
  final String v = value.trim().replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (!RegExp(r'^[A-Z]{2}[0-9]{13}$').hasMatch(v)) {
    return 'Enter a valid license number (e.g. TN0120110012345)';
  }
  return null;
}

String? validateAadhar(String? value) {
  final String? req = requiredField(value);
  if (req != null) return req;
  if (!RegExp(r'^\d{12}$').hasMatch(value!.trim())) {
    return 'Enter a valid 12-digit Aadhaar number';
  }
  return null;
}

String? validatePAN(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final String v = value.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(v)) {
    return 'Enter a valid PAN (e.g. ABCDE1234F)';
  }
  return null;
}

String? validateMobile(String? value) {
  final String? req = requiredField(value);
  if (req != null) return req;
  if (!RegExp(r'^[6-9]\d{9}$').hasMatch(value!.trim())) {
    return 'Enter a valid 10-digit mobile number';
  }
  return null;
}

/// Chains multiple validators; returns the first non-null error.
Validator composeValidators(List<Validator> validators) {
  return (String? value) {
    for (final Validator v in validators) {
      final String? error = v(value);
      if (error != null) return error;
    }
    return null;
  };
}
