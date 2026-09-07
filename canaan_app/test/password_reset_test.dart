import 'package:flutter_test/flutter_test.dart';

import 'package:canaan_app/services/password_reset_service.dart';

void main() {
  test('approval expiry and attempt lockout', () {
    expect(
        PasswordResetService.isExpired({
          'token_expires_at': DateTime.now()
              .subtract(const Duration(minutes: 1))
              .toIso8601String()
        }),
        isTrue);
    expect(
        PasswordResetService.isExpired({
          'token_expires_at': DateTime.now()
              .add(const Duration(minutes: 10))
              .toIso8601String()
        }),
        isFalse);
    expect(PasswordResetService.isExpired({}), isTrue);
    expect(PasswordResetService.isLocked({'attempts': 5}), isTrue);
    expect(PasswordResetService.isLocked({'attempts': 4}), isFalse);
    final mins = PasswordResetService.expiryFromNow()
        .difference(DateTime.now())
        .inMinutes;
    expect(mins >= 29 && mins <= 30, isTrue);
  });

  test('labels', () {
    expect(PasswordResetService.prettyType('both'), 'Username & Password');
    expect(PasswordResetService.prettyStatus('link_sent'), 'Link Sent');
    expect(PasswordResetService.prettyRole('teacher'), 'Teacher');
  });
}
