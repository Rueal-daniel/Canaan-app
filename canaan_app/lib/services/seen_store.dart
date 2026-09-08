import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which item ids the user has already seen, per feature.
/// Dashboard badges show `allIds − seenIds` so users instantly know
/// when something new arrived. Backed by SharedPreferences.
class SeenStore {
  static Future<Set<String>> getSeen(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(key)?.toSet() ?? {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> markSeen(String key, Iterable<dynamic> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final set = prefs.getStringList(key)?.toSet() ?? <String>{};
      var changed = false;
      for (final id in ids) {
        final s = id.toString();
        if (s.isNotEmpty && set.add(s)) changed = true;
      }
      if (changed) await prefs.setStringList(key, set.toList());
    } catch (_) {}
  }

  /// How many of [ids] are not in [seen].
  static int unseenCount(Iterable<dynamic> ids, Set<String> seen) {
    var n = 0;
    for (final id in ids) {
      final s = id.toString();
      if (s.isNotEmpty && !seen.contains(s)) n++;
    }
    return n;
  }

  static String? badgeFor(int count) =>
      count > 0 ? '🔴 $count' : null;
}
