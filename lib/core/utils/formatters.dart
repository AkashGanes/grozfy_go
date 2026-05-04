import 'html_utils.dart';

class Formatters {
  static String stripHtml(String? input, {bool preserveLineBreaks = false}) {
    if (preserveLineBreaks) {
      return HtmlUtils.stripHtmlPreserveLineBreaks(input);
    }
    return HtmlUtils.stripHtml(input);
  }
}

