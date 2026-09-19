import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'session_service.dart';

/// Linked Students (family / multi-child switching).
///
/// CONCEPT
///   Admin links several existing `students` rows into one family group
///   (`student_link_groups` + `student_link_members` — see
///   `supabase/student_links.sql`). A logged-in student can then switch
///   between the linked dashboards with NO logout and NO password.
///
/// SESSION MODEL (requirement §14)
///   • The LOGIN session (`SessionService`: original user id + role) is
///     NEVER touched by switching — it stays the secure authenticated
///     identity for the whole app lifetime.
///   • The ACTIVE student (which linked dashboard is being viewed) is a
///     separate local value (`_keyActiveStudentId`). It only ever holds
///     an id the server has verified as linked to the login user.
///   • Switching performs a fresh server verification on every tap, so a
///     forged id, a deleted student, or a suspended student can never be
///     opened (§11, §13).
///
/// SECURITY (§11)
///   The Canaan app authenticates against its own username/password
///   tables over the anon key (no Supabase Auth uid), so — like every
///   other feature in this codebase — authorization is enforced here in
///   the app layer at query time: [verifySwitchTarget] re-reads group
///   membership from Supabase and only returns the target row when the
///   login user and the target provably share a group.
class LinkedStudentService {
  static SupabaseClient get _client => Supabase.instance.client;

  static const groupsTable = 'student_link_groups';
  static const membersTable = 'student_link_members';

  static const _keyActiveStudentId = 'canaan_active_student_id';

  // -- active student persistence -------------------------------------------

  /// The currently viewed (active) student id, or '' when none selected.
  static Future<String> getActiveStudentId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getString(_keyActiveStudentId) ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  static Future<void> setActiveStudentId(String studentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = studentId.trim();
      if (id.isEmpty) {
        await prefs.remove(_keyActiveStudentId);
      } else {
        await prefs.setString(_keyActiveStudentId, id);
      }
    } catch (_) {}
  }

  static Future<void> clearActiveStudent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyActiveStudentId);
    } catch (_) {}
  }

  /// The login (authenticated) student id — the secure identity that
  /// switching must never replace.
  static Future<String> getLoginStudentId() async {
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.student.name) {
        return session.userId.trim();
      }
    } catch (_) {}
    return '';
  }

  /// Effective identity for ALL student data queries: the verified active
  /// student when one is selected, otherwise the login student.
  ///
  /// Callers may pass the already-known login id to save a lookup.
  static Future<String> effectiveStudentId({String loginStudentId = ''}) async {
    var loginId = loginStudentId.trim();
    loginId = loginId.isEmpty ? await getLoginStudentId() : loginId;
    final active = (await getActiveStudentId()).trim();
    if (active.isEmpty) return loginId;
    if (loginId.isEmpty) return active;
    if (active == loginId) return loginId;
    // The stored active id is only honoured while linkage is still valid.
    try {
      final ok = await isLinked(loginStudentId: loginId, targetId: active);
      if (ok) {
        final row = await fetchStudentRow(active);
        if (row != null && !AuthService.isSuspended(row)) return active;
      }
    } catch (_) {}
    return loginId;
  }

  // -- student rows ----------------------------------------------------------

  /// Full student row by id (without password), or null when deleted.
  static Future<Map<String, dynamic>?> fetchStudentRow(String studentId) async {
    final id = studentId.trim();
    if (id.isEmpty) return null;
    try {
      final row = await _client
          .from('students')
          .select('*')
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      final map = Map<String, dynamic>.from(row);
      map.remove('password');
      return map;
    } catch (_) {
      return null;
    }
  }

  static String photoUrlOf(Map<String, dynamic>? row) {
    final raw = (row?['photo_url'] ?? '').toString().trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http')) return raw;
    return 'https://pjytoxyddfrsrkzappbb.supabase.co/storage/v1/object/public/student-photos/$raw';
  }

  static String initialsOf(String? name) {
    final parts = (name ?? '').trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  static String prettySection(String? section) {
    final s = (section ?? '').trim().toLowerCase();
    if (s == 'sub-junior' || s == 'sub junior') return 'Sub Junior';
    if (s == 'junior') return 'Junior';
    if (s == 'senior') return 'Senior';
    if (s.isEmpty) return '';
    return s[0].toUpperCase() + s.substring(1);
  }

  // -- linkage reads (server-verified) ---------------------------------------

  /// Group ids containing [studentId] (fresh server read).
  static Future<Set<String>> groupIdsOf(String studentId) async {
    final id = studentId.trim();
    if (id.isEmpty) return {};
    try {
      final rows = await _client
          .from(membersTable)
          .select('group_id')
          .eq('student_id', id);
      return {
        for (final r in (rows as List))
          (r as Map)['group_id'].toString(),
      }..removeWhere((s) => s.isEmpty || s == 'null');
    } catch (_) {
      // Tables not created yet (migration not run) → no links.
      return {};
    }
  }

  /// True when [targetId] shares at least one group with [loginStudentId].
  /// The login user trivially links to themselves.
  static Future<bool> isLinked({
    required String loginStudentId,
    required String targetId,
  }) async {
    final login = loginStudentId.trim();
    final target = targetId.trim();
    if (login.isEmpty || target.isEmpty) return false;
    if (login == target) return true;
    try {
      final mine = await groupIdsOf(login);
      if (mine.isEmpty) return false;
      final rows = await _client
          .from(membersTable)
          .select('group_id')
          .eq('student_id', target)
          .inFilter('group_id', mine.toList());
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// All students linked to [loginStudentId] (including self), newest
  /// group first. Deleted students vanish automatically (no row → no
  /// tile, §13); suspended students are flagged via `status` so the UI
  /// can block switching per existing suspension rules.
  static Future<List<Map<String, dynamic>>> fetchLinkedStudents(
    String loginStudentId,
  ) async {
    final login = loginStudentId.trim();
    if (login.isEmpty) return [];
    try {
      final groupIds = await groupIdsOf(login);
      if (groupIds.isEmpty) return [];
      final memberRows = await _client
          .from(membersTable)
          .select('student_id')
          .inFilter('group_id', groupIds.toList());
      final ids = {
        for (final r in (memberRows as List))
          ((r as Map)['student_id'] ?? '').toString(),
      }..removeWhere((s) => s.isEmpty);
      ids.add(login);
      if (ids.isEmpty) return [];
      final rows = await _client
          .from('students')
          .select(
              'id, full_name, username, student_id_number, section, status, photo_url')
          .inFilter('id', ids.toList())
          .order('full_name');
      final out = <Map<String, dynamic>>[];
      for (final r in (rows as List)) {
        out.add(Map<String, dynamic>.from(r as Map));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Verifies a switch request against the SERVER (§11) and, when valid,
  /// persists the new active student. Returns the target's fresh row, or
  /// null when the switch is NOT authorized (unlinked id, deleted, or
  /// suspended student).
  static Future<Map<String, dynamic>?> verifyAndSwitch({
    required String loginStudentId,
    required String targetId,
  }) async {
    final login = loginStudentId.trim();
    final target = targetId.trim();
    if (login.isEmpty || target.isEmpty) return null;
    if (target == login) {
      await setActiveStudentId(login);
      return fetchStudentRow(login);
    }
    final linked = await isLinked(loginStudentId: login, targetId: target);
    if (!linked) return null;
    final row = await fetchStudentRow(target);
    if (row == null) return null; // deleted → gone from switch list (§13)
    if (AuthService.isSuspended(row)) return null; // suspended → blocked (§13)
    await setActiveStudentId(target);
    return row;
  }

  /// Restores the persisted active student after app restart (§14): only
  /// when linkage is still valid and the target still exists and is not
  /// suspended. Falls back to the login student otherwise.
  static Future<Map<String, dynamic>?> resolveRestoredActive({
    required String loginStudentId,
  }) async {
    final login = loginStudentId.trim();
    if (login.isEmpty) return null;
    final active = (await getActiveStudentId()).trim();
    if (active.isEmpty || active == login) {
      await setActiveStudentId(login);
      return fetchStudentRow(login);
    }
    final row = await verifyAndSwitch(
      loginStudentId: login,
      targetId: active,
    );
    if (row != null) return row;
    // Stale/invalid persisted selection → fall back to the login student.
    await setActiveStudentId(login);
    return fetchStudentRow(login);
  }

  // -- admin: group CRUD (admin screens only call these) ----------------------

  static Future<List<Map<String, dynamic>>> fetchGroups() async {
    try {
      final rows = await _client
          .from(groupsTable)
          .select('*')
          .order('updated_at', ascending: false);
      return [for (final r in (rows as List)) Map<String, dynamic>.from(r as Map)];
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchGroupMembers(
    String groupId,
  ) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return [];
    try {
      final memberRows = await _client
          .from(membersTable)
          .select('student_id')
          .eq('group_id', gid);
      final ids = [
        for (final r in (memberRows as List))
          ((r as Map)['student_id'] ?? '').toString(),
      ].where((s) => s.isNotEmpty).toList();
      if (ids.isEmpty) return [];
      final rows = await _client
          .from('students')
          .select(
              'id, full_name, username, student_id_number, section, status, photo_url')
          .inFilter('id', ids)
          .order('full_name');
      return [for (final r in (rows as List)) Map<String, dynamic>.from(r as Map)];
    } catch (_) {
      return [];
    }
  }

  /// Creates a group + memberships. Returns the new group id or ''.
  static Future<String> createGroup({
    required String groupName,
    required List<String> studentIds,
    required String adminId,
  }) async {
    final ids = studentIds.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return '';
    try {
      final now = DateTime.now().toIso8601String();
      final created = await _client
          .from(groupsTable)
          .insert({
            'group_name': groupName.trim().isEmpty ? 'Family Group' : groupName.trim(),
            'created_by': adminId.trim(),
            'created_at': now,
            'updated_at': now,
          })
          .select('id')
          .single();
      final gid = (created['id'] ?? '').toString();
      if (gid.isEmpty) return '';
      try {
        await _client.from(membersTable).insert([
          for (final sid in ids) {'group_id': gid, 'student_id': sid},
        ]);
      } catch (_) {
        // Partial insert guard: add members one by one, ignore dupes.
        for (final sid in ids) {
          try {
            await _client
                .from(membersTable)
                .insert({'group_id': gid, 'student_id': sid});
          } catch (_) {}
        }
      }
      return gid;
    } catch (_) {
      return '';
    }
  }

  static Future<bool> renameGroup({
    required String groupId,
    required String groupName,
  }) async {
    try {
      await _client.from(groupsTable).update({
        'group_name': groupName.trim().isEmpty ? 'Family Group' : groupName.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', groupId.trim());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Replaces the whole membership list (edit flow). The link becomes
  /// active only after this save completes (§3).
  static Future<bool> setGroupMembers({
    required String groupId,
    required List<String> studentIds,
  }) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return false;
    final ids = studentIds.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
    try {
      await _client.from(membersTable).delete().eq('group_id', gid);
      for (final sid in ids) {
        try {
          await _client
              .from(membersTable)
              .insert({'group_id': gid, 'student_id': sid});
        } catch (_) {}
      }
      try {
        await _client.from(groupsTable).update(
            {'updated_at': DateTime.now().toIso8601String()}).eq('id', gid);
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> removeMember({
    required String groupId,
    required String studentId,
  }) async {
    try {
      await _client
          .from(membersTable)
          .delete()
          .eq('group_id', groupId.trim())
          .eq('student_id', studentId.trim());
      try {
        await _client.from(groupsTable).update(
            {'updated_at': DateTime.now().toIso8601String()}).eq('id', groupId.trim());
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteGroup(String groupId) async {
    try {
      await _client.from(membersTable).delete().eq('group_id', groupId.trim());
    } catch (_) {}
    try {
      await _client.from(groupsTable).delete().eq('id', groupId.trim());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Lightweight student search for the admin picker (name / Student ID /
  /// username, §2). Capped for performance.
  static Future<List<Map<String, dynamic>>> searchStudents(String query) async {
    final q = query.trim();
    try {
      var req = _client
          .from('students')
          .select(
              'id, full_name, username, student_id_number, section, status, photo_url')
          .order('full_name')
          .limit(60);
      if (q.isEmpty) return [for (final r in (await req) as List) Map<String, dynamic>.from(r as Map)];
      // PostgREST OR filter across the three searchable fields.
      final like = '%$q%';
      final rows = await _client
          .from('students')
          .select(
              'id, full_name, username, student_id_number, section, status, photo_url')
          .or('full_name.ilike.$like,username.ilike.$like,student_id_number.ilike.$like')
          .order('full_name')
          .limit(60);
      return [for (final r in (rows as List)) Map<String, dynamic>.from(r as Map)];
    } catch (_) {
      return [];
    }
  }
}
