import 'package:delivery_partner_app/core/utils/html_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stripHtml removes tags and decodes entities', () {
    expect(HtmlUtils.stripHtml('<p>Hello <b>World</b></p>'), 'Hello World');
    expect(HtmlUtils.stripHtml('Tom &amp; Jerry'), 'Tom & Jerry');
  });

  test('stripHtmlPreserveLineBreaks keeps line breaks for common tags', () {
    expect(HtmlUtils.stripHtmlPreserveLineBreaks('Hi<br>There'), 'Hi\nThere');
    expect(
      HtmlUtils.stripHtmlPreserveLineBreaks('<p>One</p><p>Two</p>'),
      'One\nTwo',
    );
  });

  test('passes through empty input', () {
    expect(HtmlUtils.stripHtml(''), '');
    expect(HtmlUtils.stripHtmlPreserveLineBreaks(''), '');
  });
}

