import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canaan_app/services/seen_store.dart';

void main() {
  test('seen tracking and badge counts', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await SeenStore.getSeen('k'), isEmpty);
    await SeenStore.markSeen('k', [1, 2, '3']);
    expect(await SeenStore.getSeen('k'), {'1', '2', '3'});
    expect(SeenStore.unseenCount([1, 2, 3, 4], {'1', '3'}), 2);
    expect(SeenStore.badgeFor(0), isNull);
    expect(SeenStore.badgeFor(3), '🔴 3');
    // Re-marking is idempotent.
    await SeenStore.markSeen('k', [2]);
    expect(await SeenStore.getSeen('k'), {'1', '2', '3'});
  });
}
