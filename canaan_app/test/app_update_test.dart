import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canaan_app/services/app_update_service.dart';

Map<String, dynamic> row({
  String title = 'Canaan App Updated',
  String apk = 'https://example.com/canaan-1.2.0.apk',
  String name = '1.2.0',
  dynamic code = 4,
  bool force = false,
  String status = 'published',
}) =>
    {
      'id': 'abc',
      'title': title,
      'description': '<p>Hi</p>',
      'apk_url': apk,
      'version_name': name,
      'version_code': code,
      'force_update': force,
      'status': status,
    };

void main() {
  test('accepts a valid published update row', () {
    final u = AppUpdate.fromRow(row());
    expect(u, isNotNull);
    expect(u!.versionCode, 4);
    expect(u.forceUpdate, isFalse);
    expect(u.toRemote().apkUrl, endsWith('.apk'));
  });

  test('rejects unsafe or malformed rows', () {
    // http (not https)
    expect(AppUpdate.fromRow(row(apk: 'http://x.com/a.apk')), isNull);
    // not an apk
    expect(
        AppUpdate.fromRow(
            row(apk: 'https://example.com/a.zip')),
        isNull);
    // credentials in url
    expect(
        AppUpdate.fromRow(
            row(apk: 'https://u:p@example.com/a.apk')),
        isNull);
    // bad codes
    expect(AppUpdate.fromRow(row(code: 0)), isNull);
    expect(AppUpdate.fromRow(row(code: -2)), isNull);
    expect(AppUpdate.fromRow(row(code: 'four')), isNull);
    // missing title / version
    expect(AppUpdate.fromRow(row(title: '')), isNull);
    expect(AppUpdate.fromRow(row(name: '')), isNull);
  });

  test('update triggers ONLY on higher published versionCode', () {
    final newer = AppUpdate.fromRow(row())!;
    final same = AppUpdate.fromRow(row(code: 3))!;
    expect(AppUpdateService.shouldUpdate(3, newer), isTrue);
    // Equal codes (record edited, no new APK) → no update.
    expect(AppUpdateService.shouldUpdate(4, newer), isFalse);
    expect(AppUpdateService.shouldUpdate(3, same), isFalse);
    // Older remote → no update.
    expect(AppUpdateService.shouldUpdate(5, newer), isFalse);
    // No data → no update, never blocks startup.
    expect(AppUpdateService.shouldUpdate(null, newer), isFalse);
    expect(AppUpdateService.shouldUpdate(3, null), isFalse);
  });

  test('success box is once per version', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await AppUpdateService.successAlreadyShown('1.2.0'), isFalse);
    await AppUpdateService.markSuccessShown('1.2.0');
    expect(await AppUpdateService.successAlreadyShown('1.2.0'), isTrue);
    expect(await AppUpdateService.successAlreadyShown('1.3.0'), isFalse);
  });

  test('apk file names are filesystem-safe', () {
    final u = AppUpdate.fromRow(row(name: '1.2.0/beta:1'))!;
    final name = AppUpdateService.apkFileName(u.toRemote());
    expect(name.endsWith('.apk'), isTrue);
    expect(RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name), isTrue);
  });
}
