import 'html_utils.dart';

extension HtmlStripping on String {
  String removeHtmlTags({bool preserveLineBreaks = false}) {
    if (preserveLineBreaks) {
      return HtmlUtils.stripHtmlPreserveLineBreaks(this);
    }
    return HtmlUtils.stripHtml(this);
  }
}

