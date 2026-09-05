import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared Notice Board logic.
///
/// Uses the EXISTING `notices` table:
///   id, title, content (formatted HTML), audience, status,
///   created_by, created_by_id, read_by (text array), created_at,
///   updated_at, published_at
///
/// Audience values: `all` | `teacher` | `student` — exactly matching
/// the `notices_audience_check` constraint — always filtered
/// at the query level (never fetch-all-then-hide).
/// Read tracking uses the server-side `read_by` array: opening a
/// notice appends the reader's key, which clears its NEW indicator
/// on every device.
class NoticeService {
  static const table = 'notices';

  static const audienceAll = 'all';
  static const audienceTeachers = 'teacher';
  static const audienceStudents = 'student';

  static String normalizeAudience(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'teachers' || s == 'teacher') return audienceTeachers;
    if (s == 'students' || s == 'student') return audienceStudents;
    return audienceAll;
  }

  static String prettyAudience(String? raw) {
    switch (normalizeAudience(raw)) {
      case audienceTeachers:
        return 'Teachers';
      case audienceStudents:
        return 'Students';
      default:
        return 'All';
    }
  }

  /// Audiences a role may see — enforced in every query.
  static List<String> visibleAudiencesFor(String role) {
    if (role == 'teacher') return [audienceTeachers, audienceAll];
    if (role == 'student') return [audienceStudents, audienceAll];
    return [audienceAll, audienceTeachers, audienceStudents];
  }

  static const _fullMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  /// `September 5, 2026`.
  static String prettyDate(String? raw) {
    final d = _parse(raw);
    if (d == null) return (raw ?? '').split('T').first;
    return '${_fullMonths[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// `September 5, 2026 • 5:30 PM`.
  static String prettyDateTime(String? raw) {
    final d = _parse(raw);
    if (d == null) return (raw ?? '').split('T').first;
    var h = d.hour % 12;
    if (h == 0) h = 12;
    final mm = d.minute.toString().padLeft(2, '0');
    final ap = d.hour < 12 ? 'AM' : 'PM';
    return '${prettyDate(raw)} • $h:$mm $ap';
  }

  static DateTime? _parse(String? raw) {
    final src = (raw ?? '').trim();
    if (src.isEmpty) return null;
    try {
      return DateTime.parse(src).toLocal();
    } catch (_) {
      return null;
    }
  }

  /// Plain-text version of the formatted HTML (search + previews).
  static String plainTextOf(String? html) {
    var s = (html ?? '').replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'</(p|h1|h2|h3|ul|ol|li|div)>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<[^>]*>'), '');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');
    return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  // -- read tracking ---------------------------------------------------------

  static List<String> readersOf(Map<String, dynamic> row) {
    final v = row['read_by'];
    if (v is List) {
      return v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return [];
  }

  static bool isUnread(Map<String, dynamic> row, String readKey) {
    if (readKey.isEmpty) return true;
    return !readersOf(row).contains(readKey);
  }

  /// Appends [readKey] to the server-side `read_by` array (best-effort).
  static Future<void> markAsRead(
    SupabaseClient client,
    int noticeId,
    List<String> current,
    String readKey,
  ) async {
    if (readKey.isEmpty || current.contains(readKey)) return;
    try {
      await client.from(table).update({
        'read_by': [...current, readKey],
      }).eq('id', noticeId);
    } catch (_) {}
  }
}
