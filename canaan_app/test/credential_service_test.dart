import 'package:flutter_test/flutter_test.dart';

import 'package:canaan_app/services/credential_service.dart';

void main() {
  test('labels and table mapping', () {
    expect(CredentialService.userTable('teacher'), 'teachers');
    expect(CredentialService.userTable('student'), 'students');
    expect(CredentialService.prettyShortType('username_and_password'),
        'Username & Password Change');
    expect(CredentialService.prettyStatus('approved'), 'Approved');
    expect(
        CredentialService.prettyShortDate('2026-09-08T10:00:00+00:00'),
        'Sept 8, 2026');
  });

  test('password rule', () {
    expect(CredentialService.validateNewPassword(''), isNotNull);
    expect(CredentialService.validateNewPassword('12345'), isNotNull);
    expect(CredentialService.validateNewPassword('123456'), isNull);
  });
}
