/// Shared Prayer Request logic for Admin / Teacher / Student.
///
/// Backed by (see `supabase/prayer_requests.sql` — run once):
///   `prayer_requests`         (id, user_id, full_name, role, title,
///     description, created_at, updated_at) — ONE shared community feed,
///     never separate tables per role.
///   `prayer_request_replies`  (id, prayer_request_id → requests.id
///     ON DELETE CASCADE, admin_id, admin_name, comment, created_at,
///     updated_at) — at most ONE admin reply per request.
///
/// Only display-safe fields exist here (name + role + text). No emails,
/// phones, usernames or passwords are ever read or stored by this
/// feature.
///
/// Rules (enforced in the app layer):
///   Everyone reads the whole shared feed; anyone submits.
///   ONLY admins write/edit/delete replies.
///   Owners may delete their own request; admins may delete any request.
class PrayerRequestService {
  static const requestsTable = 'prayer_requests';
  static const repliesTable = 'prayer_request_replies';

  static const roleAdmin = 'admin';
  static const roleTeacher = 'teacher';
  static const roleStudent = 'student';

  static const roles = [roleAdmin, roleTeacher, roleStudent];

  static String normalizeRole(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'admin' || s == 'administrator' || s == 'canaan administrator') {
      return roleAdmin;
    }
    if (s == 'teacher' || s == 'teachers') return roleTeacher;
    return roleStudent;
  }

  static String prettyRole(String? raw) {
    switch (normalizeRole(raw)) {
      case roleAdmin:
        return 'Admin';
      case roleTeacher:
        return 'Teacher';
      default:
        return 'Student';
    }
  }

  static bool isAdmin(String role) =>
      normalizeRole(role) == roleAdmin;

  static int requestIdOf(Map<String, dynamic> row) =>
      (row['id'] as num?)?.toInt() ?? -1;

  static String userIdOf(Map<String, dynamic> row) =>
      (row['user_id'] ?? '').toString();

  /// Owners delete their own request; admins delete any request.
  /// An empty [userId] can never authorize an owner delete.
  static bool canDeleteRequest(
    Map<String, dynamic> row, {
    required String role,
    required String userId,
  }) {
    if (isAdmin(role)) return true;
    if (userId.isEmpty) return false;
    return userIdOf(row) == userId;
  }

  static const _fullMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  static DateTime? _parse(String? raw) {
    final src = (raw ?? '').trim();
    if (src.isEmpty) return null;
    try {
      return DateTime.parse(src).toLocal();
    } catch (_) {
      return null;
    }
  }

  /// `September 12, 2026`.
  static String prettyDate(String? raw) {
    final d = _parse(raw);
    if (d == null) return (raw ?? '').split('T').first;
    return '${_fullMonths[d.month - 1]} ${d.day}, ${d.year}';
  }

  static DateTime? createdAtOf(Map<String, dynamic> row) =>
      _parse(row['created_at']?.toString());

  /// Newest first (default) or oldest first.
  static List<Map<String, dynamic>> sorted(
    List<Map<String, dynamic>> requests, {
    bool newestFirst = true,
  }) {
    final list = List<Map<String, dynamic>>.from(requests);
    list.sort((a, b) {
      final da = createdAtOf(a);
      final db = createdAtOf(b);
      if (da == null && db == null) {
        return (b['id'] as num? ?? 0).compareTo(a['id'] as num? ?? 0);
      }
      if (da == null) return 1;
      if (db == null) return -1;
      return newestFirst ? db.compareTo(da) : da.compareTo(db);
    });
    return list;
  }

  /// Search (title + submitter name) + role filter, applied together.
  static List<Map<String, dynamic>> applySearchFilter(
    List<Map<String, dynamic>> requests, {
    String search = '',
    String roleFilter = '',
  }) {
    final q = search.trim().toLowerCase();
    final rf = normalizeRole(roleFilter.isEmpty ? '' : roleFilter);
    final filterOn = roleFilter.trim().isNotEmpty;
    return requests.where((r) {
      if (filterOn && normalizeRole(r['role']?.toString()) != rf) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay = '${r['title']} ${r['full_name']}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  /// `prayer:12` / `prayer:12:reply` → 12 (notification deep-link focus).
  static int? focusIdFromRelatedId(String? relatedId) {
    final parts = (relatedId ?? '').split(':');
    if (parts.length < 2 || parts[0] != 'prayer') return null;
    return int.tryParse(parts[1]);
  }
}
