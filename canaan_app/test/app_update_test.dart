import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canaan_app/services/app_update_service.dart';

void main() {
  test('parses a valid update config', () {
    final u = RemoteUpdate.parse({
      'versionName': '1.1.0',
      'versionCode': 2,
      'apkUrl': 'https://canaan-ss.site.je/app/canaan-1.1.0.apk',
      'updateTitle': 'Canaan Update Available',
      'updateDescription': 'A new version is available.',
      'whatsNew': ['New feature added', 'Bug fixes'],
      'forceUpdate': false,
    });
    expect(u, isNotNull);
    expect(u!.versionCode, 2);
    expect(u.whatsNew, hasLength(2));
    expect(u.forceUpdate, isFalse);
  });

  test('rejects unsafe or malformed configs', () {
    // http (not https)
    expect(
        RemoteUpdate.parse({
          'versionName': '1.1.0',
          'versionCode': 2,
          'apkUrl': 'http://evil.example.com/app.apk',
        }),
        isNull);
    // not an apk
    expect(
        RemoteUpdate.parse({
          'versionName': '1.1.0',
          'versionCode': 2,
          'apkUrl': 'https://example.com/app.zip',
        }),
        isNull);
    // credentials embedded in url
    expect(
        RemoteUpdate.parse({
          'versionName': '1.1.0',
          'versionCode': 2,
          'apkUrl': 'https://user:pass@example.com/app.apk',
        }),
        isNull);
    // bad version code
    expect(
        RemoteUpdate.parse({
          'versionName': '1.1.0',
          'versionCode': 0,
          'apkUrl': 'https://example.com/app.apk',
        }),
        isNull);
    expect(RemoteUpdate.parse({'nope': true}), isNull);
    expect(RemoteUpdate.parse('string'), isNull);
  });

  test('update triggers ONLY on higher remote versionCode', () {
    RemoteUpdate remote(int code) => RemoteUpdate(
          versionName: 'x',
          versionCode: code,
          apkUrl: 'https://example.com/a.apk',
          updateTitle: 't',
          updateDescription: 'd',
          whatsNew: const [],
          forceUpdate: false,
        );
    expect(AppUpdateService.shouldUpdate(1, remote(2)), isTrue);
    // Same code (e.g. only website/db changed) → no update.
    expect(AppUpdateService.shouldUpdate(2, remote(2)), isFalse);
    // Older remote → no update.
    expect(AppUpdateService.shouldUpdate(3, remote(2)), isFalse);
    // No data → no update, never blocks startup.
    expect(AppUpdateService.shouldUpdate(null, remote(2)), isFalse);
    expect(AppUpdateService.shouldUpdate(1, null), isFalse);
  });

  test('success box is once per version', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await AppUpdateService.successAlreadyShown('1.1.0'), isFalse);
    await AppUpdateService.markSuccessShown('1.1.0');
    expect(await AppUpdateService.successAlreadyShown('1.1.0'), isTrue);
    expect(await AppUpdateService.successAlreadyShown('1.2.0'), isFalse);
  });

  test('apk file names are filesystem-safe', () {
    const u = RemoteUpdate(
      versionName: '1.1.0/beta:1',
      versionCode: 2,
      apkUrl: 'https://example.com/a.apk',
      updateTitle: 't',
      updateDescription: 'd',
      whatsNew: [],
      forceUpdate: false,
    );
    final name = AppUpdateService.apkFileName(u);
    expect(name.endsWith('.apk'), isTrue);
    expect(RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name), isTrue);
  });
}
