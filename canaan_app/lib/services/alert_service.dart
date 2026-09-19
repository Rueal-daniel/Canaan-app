import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'leaderboard_service.dart';
import 'leave_service.dart';
import 'linked_student_service.dart';
import 'notification_service.dart';
import 'session_service.dart';

/// Admin Alert system — urgent/important instructions with a STRICT
/// 24-hour lifetime, separate from the Notice Board.
///
/// TABLES (see `supabase/alerts.sql`):
///   alerts            → title, message, type, audience, section, status,
///                       published_at, expires_at (published_at + 24h).
///   alert_recipients  → per-user read state ONLY (never the message).
///
/// EXPIRY (§33–§41): every query for non-admin users hard-filters
/// `status='published' AND expires_at > now()`. Expired rows remain for
/// Admin audit (shown "Expired") but are never delivered. Re-publishing
/// means a NEW alert — the lifetime is never extended.
///
/// TARGETING (§17 — enforced at QUERY level, never fetch-all-then-hide):
/// teachers see Teacher+own-section, Teacher+all, Both+own-section,
/// Both+all; students see the mirror set. The section always comes from
/// the VERIFIED row id (server-side), never a client value.
class AlertService {
  static SupabaseClient get _client => Supabase.instance.client;

  static const table = 'alerts';
  static const recipientsTable = 'alert_recipients';

  // -- alert types ------------------------------------------------------------
  static const typeImportant = 'important';
  static const typeReminder = 'reminder';
  static const typeInstruction = 'instruction';
  static const typeUrgent = 'urgent';
  static const typeGeneral = 'general';

  static const types = [
    typeImportant,
    typeReminder,
    typeInstruction,
    typeUrgent,
    typeGeneral,
  ];

  // -- audiences ----------------------------------------------------------------
  static const toTeachers = 'teachers';
  static const toStudents = 'students';
  static const toBoth = 'both';

  // -- status ----------------------------------------------------------------------
  static const statusDraft = 'draft';
  static const statusPublished = 'published';

  /// Lifetime is EXACTLY 24 hours — no option exists to extend it.
  static const expiryHours = 24;

  static String normalizeSection(String? section) =>
      LeaveService.normalizeSection(section);

  /// 'all' stays 'all'; everything else normalizes to a section slug.
  static String normalizeTargetSection(String? section) {
    final s = (section ?? '').trim().toLowerCase();
    if (s.isEmpty || s == 'all' || s == 'all sections') return 'all';
    return normalizeSection(s);
  }

  static String normalizeType(String? type) {
    final t = (type ?? '').trim().toLowerCase();
    return types.contains(t) ? t : typeGeneral;
  }

  static String normalizeSendTo(String? sendTo) {
    final s = (sendTo ?? '').trim().toLowerCase();
    if (s == toTeachers || s == 'teacher') return toTeachers;
    if (s == toStudents || s == 'student') return toStudents;
    return toBoth;
  }

  static String prettySection(String? section) {
    final s = (section ?? '').trim().toLowerCase();
    if (s.isEmpty || s == 'all') return 'All Sections';
    if (s == 'sub-junior' || s == 'sub junior') return 'Sub Junior';
    if (s == 'junior') return 'Junior';
    if (s == 'senior') return 'Senior';
    return (section ?? '').trim();
  }

  static String prettySendTo(String? sendTo) {
    switch (normalizeSendTo(sendTo)) {
      case toTeachers:
        return 'Teachers';
      case toStudents:
        return 'Students';
      default:
        return 'Teachers & Students';
    }
  }

  static String prettyType(String? type) {
    switch (normalizeType(type)) {
      case typeImportant:
        return 'Important';
      case typeReminder:
        return 'Reminder';
      case typeInstruction:
        return 'Instruction';
      case typeUrgent:
        return 'Urgent';
      default:
        return 'General';
    }
  }

  static String prettyDateTime(String? raw) {
    final src = (raw ?? '').trim();
    if (src.isEmpty) return '';
    try {
      final d = DateTime.parse(src).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final ampm = d.hour < 12 ? 'AM' : 'PM';
      return '${months[d.month - 1]} ${d.day}, ${d.year} · $hour12:${d.minute.toString().padLeft(2, '0')} $ampm';
    } catch (_) {
      return src;
    }
  }

  static bool isExpired(Map<String, dynamic> alert, {DateTime? now}) {
    final exp = DateTime.tryParse(
        (alert['expires_at'] ?? '').toString());
    if (exp == null) return true; // no expiry = never active
    return !(exp.isAfter(now ?? DateTime.now()));
  }

  static String nowIso() => DateTime.now().toUtc().toIso8601String();

  // -- admin: create / edit / publish / delete -----------------------------------

  static Future<String> create({
    required String title,
    required String message,
    required String alertType,
    required String sendTo,
    required String section,
    required String adminId,
    bool publishNow = false,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      final published = publishNow;
      final payload = <String, dynamic>{
        'title': title.trim(),
        'message': message.trim(),
        'alert_type': normalizeType(alertType),
        'send_to': normalizeSendTo(sendTo),
        'section': normalizeTargetSection(section),
        'status': published ? statusPublished : statusDraft,
        'created_by': adminId.trim(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      if (published) {
        payload['published_at'] = now.toIso8601String();
        payload['expires_at'] =
            now.add(const Duration(hours: expiryHours)).toIso8601String();
      }
      final created = await _client
          .from(table)
          .insert(payload)
          .select('id')
          .single();
      final id = (created['id'] ?? '').toString();
      if (id.isNotEmpty && published) {
        await _afterPublish(id);
      }
      return id;
    } catch (_) {
      return '';
    }
  }

  static Future<bool> update({
    required String alertId,
    required String title,
    required String message,
    required String alertType,
    required String sendTo,
    required String section,
  }) async {
    try {
      await _client.from(table).update({
        'title': title.trim(),
        'message': message.trim(),
        'alert_type': normalizeType(alertType),
        'send_to': normalizeSendTo(sendTo),
        'section': normalizeTargetSection(section),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', alertId.trim());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Publishes a draft: stamps published_at + expires_at (+24h, fixed),
  /// fans out recipient rows + bell notifications. Every publication
  /// starts its OWN 24-hour countdown (§39).
  static Future<bool> publish(String alertId) async {
    try {
      final now = DateTime.now().toUtc();
      await _client.from(table).update({
        'status': statusPublished,
        'published_at': now.toIso8601String(),
        'expires_at':
            now.add(const Duration(hours: expiryHours)).toIso8601String(),
        'updated_at': now.toIso8601String(),
      }).eq('id', alertId.trim());
      await _afterPublish(alertId.trim());
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> unpublish(String alertId) async {
    try {
      await _client.from(table).update({
        'status': statusDraft,
        'published_at': null,
        'expires_at': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', alertId.trim());
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> remove(String alertId) async {
    try {
      await _client
          .from(recipientsTable)
          .delete()
          .eq('alert_id', alertId.trim());
    } catch (_) {}
    try {
      await _client.from(table).delete().eq('id', alertId.trim());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Post-publish fan-out: recipient rows for the targeted users +
  /// bell notifications (expiring with the alert). Fire-and-forget —
  /// publishing never fails because of this.
  static Future<void> _afterPublish(String alertId) async {
    try {
      final row = await _client
          .from(table)
          .select('*')
          .eq('id', alertId)
          .maybeSingle();
      if (row == null) return;
      final map = Map<String, dynamic>.from(row);
      final userIds = await resolveRecipientIds(
        sendTo: (map['send_to'] ?? '').toString(),
        section: (map['section'] ?? '').toString(),
      );
      if (userIds.isNotEmpty) {
        final role = (map['send_to'] ?? '').toString();
        for (final uid in userIds) {
          try {
            await _client.from(recipientsTable).insert({
              'alert_id': alertId,
              'user_id': uid,
              'role': role,
              'section': (map['section'] ?? '').toString(),
            });
          } catch (_) {}
        }
      }
      try {
        final exp = DateTime.tryParse(
            (map['expires_at'] ?? '').toString());
        await NotificationService.alertPublished(
          alertId: alertId,
          title: (map['title'] ?? '').toString(),
          sendTo: (map['send_to'] ?? '').toString(),
          section: (map['section'] ?? '').toString(),
          expiresAt: exp,
        );
      } catch (_) {}
    } catch (_) {}
  }

  /// Targeted user ids for fan-out (existing students/teachers tables —
  /// never duplicated). Section 'all' covers every section.
  static Future<Set<String>> resolveRecipientIds({
    required String sendTo,
    required String section,
  }) async {
    final out = <String>{};
    final audience = normalizeSendTo(sendTo);
    final sec = normalizeTargetSection(section);
    final sections =
        sec == 'all' ? ['sub-junior', 'junior', 'senior'] : [sec];
    try {
      if (audience == toTeachers || audience == toBoth) {
        for (final s in sections) {
          out.addAll(await _idsOf('teachers', s));
        }
      }
      if (audience == toStudents || audience == toBoth) {
        for (final s in sections) {
          out.addAll(await _idsOf('students', s));
        }
      }
    } catch (_) {}
    return out;
  }

  static Future<List<String>> _idsOf(String table, String section) async {
    try {
      final rows = await _client
          .from(table)
          .select('id')
          .eq('section', section);
      return [
        for (final r in (rows as List))
          ((r as Map)['id'] ?? '').toString(),
      ].where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchAll() async {
    try {
      final rows = await _client
          .from(table)
          .select('*')
          .order('created_at', ascending: false);
      return [
        for (final r in (rows as List))
          Map<String, dynamic>.from(r as Map)
      ];
    } catch (_) {
      return [];
    }
  }

  // -- targeted reads (teachers / students — query-level enforcement) -------------

  /// Resolves the verified (userId, section) scope for an inbox, popup or
  /// badge. Falls back to the secure login/active identity when the
  /// passed id is empty — the section ALWAYS comes from the server-side
  /// row, never from a client value.
  static Future<({String userId, String section})> resolveScope({
    required String role,
    required String userId,
  }) async {
    final r = role.trim().toLowerCase();
    var id = userId.trim();
    try {
      if (id.isEmpty) {
        if (r == 'teacher') {
          final session = await SessionService.getSession();
          if (session != null &&
              session.role == UserRole.teacher.name) {
            id = session.userId.trim();
          }
        } else if (r == 'student') {
          id = await LinkedStudentService.effectiveStudentId();
        }
      }
      if (id.isEmpty) return (userId: '', section: '');
      final section = r == 'teacher'
          ? await LeaderboardService.teacherSectionOf(id)
          : await LeaderboardService.studentSectionOf(id);
      // Suspended users get no scope (existing suspension rules apply).
      try {
        final table = r == 'teacher' ? 'teachers' : 'students';
        final row = await _client
            .from(table)
            .select('status')
            .eq('id', id)
            .maybeSingle();
        if (AuthService.isSuspended(row)) {
          return (userId: '', section: '');
        }
      } catch (_) {}
      return (userId: id, section: section);
    } catch (_) {
      return (userId: '', section: '');
    }
  }

  /// Active alerts for a role + section, newest first.
  ///
  /// Server-side filters: status='published', expires_at > now(), and the
  /// exact (send_to, section) targeting matrix — unauthorized rows are
  /// never retrieved, not merely hidden (§17).
  static Future<List<Map<String, dynamic>>> fetchActive({
    required String role,
    required String section,
  }) async {
    final r = role.trim().toLowerCase();
    final sec = normalizeSection(section);
    if (sec.isEmpty) return [];
    final own =
        r == 'teacher' ? toTeachers : toStudents;
    try {
      final rows = await _client
          .from(table)
          .select('*')
          .eq('status', statusPublished)
          .gt('expires_at', nowIso())
          .or('and(send_to.eq.$own,section.eq.$sec),'
              'and(send_to.eq.$own,section.eq.all),'
              'and(send_to.eq.$toBoth,section.eq.$sec),'
              'and(send_to.eq.$toBoth,section.eq.all)')
          .order('published_at', ascending: false);
      final out = <Map<String, dynamic>>[];
      final now = DateTime.now();
      for (final row in (rows as List)) {
        final m = Map<String, dynamic>.from(row as Map);
        if (!isExpired(m, now: now)) out.add(m); // belt-and-braces
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Read state for [userId] over [alertIds]: alertId → isRead.
  static Future<Map<String, bool>> readStates(
    String userId,
    List<String> alertIds,
  ) async {
    final uid = userId.trim();
    if (uid.isEmpty || alertIds.isEmpty) return {};
    try {
      final rows = await _client
          .from(recipientsTable)
          .select('alert_id,is_read')
          .eq('user_id', uid)
          .inFilter('alert_id', alertIds);
      final list = List<Map<String, dynamic>>.from(rows);
      return {
        for (final m in list)
          (m['alert_id'] ?? '').toString(): m['is_read'] == true,
      };
    } catch (_) {
      return {};
    }
  }

  /// Unread ACTIVE alert count for badges (expired never counted).
  static Future<int> unreadCount({
    required String role,
    required String section,
    required String userId,
  }) async {
    try {
      final active =
          await fetchActive(role: role, section: section);
      if (active.isEmpty) return 0;
      final ids = [
        for (final a in active) (a['id'] ?? '').toString()
      ].where((s) => s.isNotEmpty).toList();
      final states = await readStates(userId, ids);
      var n = 0;
      for (final id in ids) {
        if (states[id] != true) n++;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }

  /// Marks ONE user's own alert as read (upsert keyed by the verified
  /// user id — nobody can mark another user's alert).
  static Future<void> markAsRead({
    required String alertId,
    required String userId,
    required String role,
    required String section,
  }) async {
    final aid = alertId.trim();
    final uid = userId.trim();
    if (aid.isEmpty || uid.isEmpty) return;
    try {
      await _client.from(recipientsTable).upsert(
        {
          'alert_id': aid,
          'user_id': uid,
          'role': role.trim().toLowerCase(),
          'section': normalizeSection(section),
          'is_read': true,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'alert_id,user_id',
      );
    } catch (_) {}
  }
}
