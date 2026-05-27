import 'html_utils.dart';

class Formatters {
  static String stripHtml(String? input, {bool preserveLineBreaks = false}) {
    if (preserveLineBreaks) {
      return HtmlUtils.stripHtmlPreserveLineBreaks(input);
    }
    return HtmlUtils.stripHtml(input);
  }
}

// =============================================================================
// Centralised date & time formatting for the entire app.
//
// Conventions:
//   • Display date  → DD/MM/YYYY           e.g. 27/05/2026
//   • Display time  → 12-hour, H:MM AM/PM  e.g. 2:30 PM
//   • API date      → YYYY-MM-DD           e.g. 2026-05-27  (server format)
//   • Relative time → "Just now" / "5m ago" / "Yesterday" / DD/MM/YYYY
// =============================================================================

class AppDateFormat {
  AppDateFormat._();

  // ── Display formatters ────────────────────────────────────────────────────

  /// DD/MM/YYYY — primary date display format.
  static String date(DateTime? d) {
    if (d == null) return '';
    return '${_p(d.day)}/${_p(d.month)}/${d.year}';
  }

  /// Parse a raw server string (YYYY-MM-DD or ISO-8601) → DD/MM/YYYY.
  /// Falls back to the original string on failure.
  static String dateFromString(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    if (raw.length >= 10) {
      final parts = raw.substring(0, 10).split('-');
      if (parts.length == 3 && parts[0].length == 4) {
        return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
    }
    final dt = DateTime.tryParse(raw);
    return dt != null ? date(dt) : raw;
  }

  /// H:MM AM/PM — 12-hour clock (e.g. 2:30 PM).
  static String time(DateTime? d) {
    if (d == null) return '';
    final h = d.hour;
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$hour12:${_p(d.minute)} ${h >= 12 ? 'PM' : 'AM'}';
  }

  /// DD/MM/YYYY, H:MM AM/PM — combined date and time.
  static String dateTime(DateTime? d) {
    if (d == null) return '';
    return '${date(d)}, ${time(d)}';
  }

  /// 'January 2026' — full month name and year.
  static String monthYear(DateTime d) =>
      '${_fullMonths[d.month - 1]} ${d.year}';

  /// Build a month-year label from separate 1-based month + year integers.
  static String monthYearFromParts(int month, int year) {
    if (month < 1 || month > 12) return '$year';
    return '${_fullMonths[month - 1]} $year';
  }

  /// 'Jan 2026' — abbreviated month name and year.
  static String shortMonthYear(DateTime d) =>
      '${_shortMonths[d.month - 1]} ${d.year}';

  /// Relative timestamp with graceful fallback.
  /// 'Just now' → 'Xm ago' → 'Xh ago' → 'Yesterday' → 'Xd ago' → DD/MM/YYYY.
  static String timeAgo(DateTime? d) {
    if (d == null) return 'Just now';
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return date(d);
  }

  /// Human-readable duration: '1h 30m' / '45 min' / '30s'.
  static String duration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    if (d.inMinutes > 0) return '${d.inMinutes} min';
    return '${d.inSeconds}s';
  }

  // ── API / storage formatters ───────────────────────────────────────────────

  /// YYYY-MM-DD — format expected by the Frappe/ERPNext backend.
  static String apiDate(DateTime d) =>
      '${d.year}-${_p(d.month)}-${_p(d.day)}';

  // ── Private ───────────────────────────────────────────────────────────────

  static String _p(int n) => n.toString().padLeft(2, '0');

  static const _shortMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _fullMonths = [
    'January', 'February', 'March', 'April',
    'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December',
  ];
}

