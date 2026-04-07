import 'package:delivery_partner_app/core/models/app_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NotificationLog.fromJson strips HTML from subject and message', () {
    final log = NotificationLog.fromJson({
      'name': 'abc',
      'subject': '<strong>Admin</strong> assigned <b>Task</b> &amp; more',
      'email_content': '<div><p>Hello<br>World</p></div>',
      'read': 0,
      'creation': '2026-04-07 16:37:29.669249',
    });

    expect(log.subject, 'Admin assigned Task & more');
    expect(log.message, 'Hello\nWorld');
  });
}

