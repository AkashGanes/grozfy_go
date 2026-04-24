import '../models/app_models.dart';
import 'app_strings.dart';

class LocalizedText {
  const LocalizedText._();

  static String t(
    String languageCode,
    String key, [
    Map<String, String> params = const <String, String>{},
  ]) {
    return AppStrings.format(languageCode, key, params);
  }

  static String orderStatus(String languageCode, OrderProgressStatus status) {
    return AppStrings.get(languageCode, status.localizationKey);
  }

  static String verificationStatus(
    String languageCode,
    VerificationStatus status,
  ) {
    return AppStrings.get(languageCode, status.localizationKey);
  }

  static String externalDeliveryStatus(
    String languageCode,
    ExternalDeliveryStatus status,
  ) {
    return AppStrings.get(languageCode, status.localizationKey);
  }

  static String resolveAiMessage(
    String languageCode,
    dynamic value,
  ) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Map) {
      final Map<String, dynamic> map = value.cast<String, dynamic>();
      final String? key = _firstNonBlank([
        map['message_key']?.toString(),
        map['key']?.toString(),
      ]);
      if (key != null) {
        final Map<String, String> params = <String, String>{};
        final dynamic rawParams = map['message_args'] ?? map['args'];
        if (rawParams is Map) {
          for (final entry in rawParams.entries) {
            params[entry.key.toString()] = entry.value?.toString() ?? '';
          }
        }
        return AppStrings.format(languageCode, key, params);
      }

      final String? message = _firstNonBlank([
        map['message']?.toString(),
        map['text']?.toString(),
        map['content']?.toString(),
      ]);
      if (message != null) {
        return message;
      }
    }
    return value.toString();
  }

  static String resolveTripNotes(String languageCode, String tripNotes) {
    final String trimmed = tripNotes.trim();
    final String lower = trimmed.toLowerCase();
    if (lower.startsWith('return_trip_for:')) {
      final String orderName = trimmed.substring('return_trip_for:'.length).trim();
      return AppStrings.format(
        languageCode,
        'return_trip_note',
        <String, String>{'order_name': orderName},
      );
    }
    return trimmed;
  }

  static String returnTripMarker(String orderName) => 'return_trip_for:$orderName';

  static String? _firstNonBlank(List<String?> values) {
    for (final value in values) {
      final String trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }
}
