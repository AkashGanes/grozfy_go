import 'package:html/parser.dart' as html_parser;

class HtmlUtils {
  static String stripHtml(String? input) {
    final String value = (input ?? '').toString();
    if (value.isEmpty) return value;

    try {
      final document = html_parser.parse(value);
      return (document.body?.text ?? '').trim();
    } catch (_) {
      return value;
    }
  }

  static String stripHtmlPreserveLineBreaks(String? input) {
    final String value = (input ?? '').toString();
    if (value.isEmpty) return value;

    try {
      final withLineBreaks = value
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n');

      final document = html_parser.parse(withLineBreaks);
      return (document.body?.text ?? '').trim();
    } catch (_) {
      return value;
    }
  }
}

