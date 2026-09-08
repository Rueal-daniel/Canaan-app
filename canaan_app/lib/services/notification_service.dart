import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_service.dart';

/// Central, event-based notification system for the Canaan app.
///
/// Existing feature tables (attendance_reports, notices,
/// student_leave_applications, lesson_plans, memory_verses,
/// credential_change_requests, password_reset_requests, download_center,
/// teacher_attendance, ...) remain the SOURCE OF TRUTH. A notification
/// stores only: type/title/message + a [related_id] pointer back to the
/// original record + a [destination] route key. It never duplicates
/// names, emails, phones, passwords or full feature data.
///
/// Tables (see `supabase/notifications.sql` — run once in Supabase):
///   notifications            → ONE row per event.
///   notification_recipients  → who receives it + read/unread state.
///                              1 notice to 100 users = 1 event + 100 rows.
///   notification_archive     → cold storage for old snapshots.
///
/// Every public method is defensive: if the notification tables have not
/// been created yet (migration not run) the call silently does nothing,
/// so existing features can never break because of notifications.
class NotificationService {
  static SupabaseClient get _client => Supabase.instance.client;

  static const eventsTable = 'notifications';
  static const recipientsTable = 'notification_recipients';

  // -- notification types (controlled vocabulary) ---------------------------
  static const typeAttendance = 'attendance';
  static const typeNotice = 'notice';
  static const typeLeave = 'leave';
  static const typeLessonPlan = 'lesson_plan';
  static const typeMemoryVerse = 'memory_verse';
  static const typeAuthentication = 'authentication';
  static const typeStudentApplication = 'student_application';
  static const typeDownload = 'download';
  static const typeWebsiteUpdate = 'website_update';

  // -- audiences -------------------------------------------------------------
  static const audienceAll = 'all';
  static const audienceStudents = 'students';
  static const audienceTeachers = 'teachers';
  static const audienceAdmins = 'admins';
  static const audienceSection = 'section';
  static const audienceIndividual = 'individual';

  // -- destinations (route keys resolved by NotificationNavigation) ---------
  static const destDashboard = 'dashboard';
  static const destAttendance = 'attendance'; // Student → My Attendance
  static const destMyAttendance = 'my_attendance'; // Teacher → My Attendance
  static const destNoticeBoard = 'notice_board';
  static const destLeaveApplication = 'leave_application';
  static const destStudentApplications = 'student_applications';
  static const destStudentReports = 'student_reports'; // Admin → StdReport
  static const destLessonPlan = 'lesson_plan';
  static const destMemoryVerse = 'memory_verse';
  static const destCredentials = 'credentials'; // user → Change Credentials
  static const destCredentialsAdmin = 'credentials_admin'; // admin requests
  static const destPasswordResetAdmin = 'password_reset_admin';
  static const destDownloadCenter = 'download_center';

  static const _archiveLastRunKey = 'canaan_notif_archive_last_run';
  static const _archiveRetentionDays = 90;

  // -- identity ---------------------------------------------------------------

  /// The logged-in user's Supabase row id (students/teachers/admin id).
  /// Notification recipients are keyed by exactly this id.
  static Future<String> currentUserId() async {
    try {
      final session = await SessionService.getSession();
      return session?.userId ?? '';
    } catch (_) {
      return '';
    }
  }

  // -- reads ------------------------------------------------------------------

  /// My notifications, newest first. Expired events are filtered out.
  static Future<List<AppNotification>> fetchMine(
    String userId, {
    int limit = 100,
  }) async {
    if (userId.isEmpty) return [];
    try {
      // Single round trip via the FK to notifications; falls back to a
      // two-step fetch when embedded selects are unavailable.
      try {
        final rows = await _client
            .from(recipientsTable)
            .select(
              'id,is_read,read_at,created_at,user_id,'
              'notifications(id,type,title,message,related_id,destination,'
              'audience_type,section,created_at,expires_at)',
            )
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(limit);
        final out = <AppNotification>[];
        for (final r in (rows as List)) {
          final n = AppNotification.fromJoined(Map<String, dynamic>.from(r as Map));
          if (n != null && !n.isExpired) out.add(n);
        }
        return out;
      } catch (_) {
        return await _fetchMineTwoStep(userId, limit: limit);
      }
    } catch (_) {
      return [];
    }
  }

  static Future<List<AppNotification>> _fetchMineTwoStep(
    String userId, {
    int limit = 100,
  }) async {
    try {
      final recips = await _client
          .from(recipientsTable)
          .select('id,is_read,read_at,created_at,user_id,notification_id')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      final recipList = List<Map<String, dynamic>>.from(recips);
      if (recipList.isEmpty) return [];
      final ids = recipList
          .map((r) => (r['notification_id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
      if (ids.isEmpty) return [];
      final events = await _client
          .from(eventsTable)
          .select(
            'id,type,title,message,related_id,destination,'
            'audience_type,section,created_at,expires_at',
          )
          .inFilter('id', ids);
      final byId = {
        for (final e in (events as List))
          (e as Map)['id'].toString(): Map<String, dynamic>.from(e),
      };
      final out = <AppNotification>[];
      for (final r in recipList) {
        final event = byId[(r['notification_id'] ?? '').toString()];
        if (event == null) continue;
        final n = AppNotification.fromParts(r, event);
        if (!n.isExpired) out.add(n);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<int> unreadCount(String userId) async {
    if (userId.isEmpty) return 0;
    try {
      final rows = await _client
          .from(recipientsTable)
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// Realtime stream of MY recipient rows. The bell re-fetches the joined
  /// list whenever this emits — badge updates with no refresh.
  static Stream<List<Map<String, dynamic>>> watchMine(String userId) {
    try {
      return _client
          .from(recipientsTable)
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .map((rows) => List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      return const Stream.empty();
    }
  }

  static Future<void> markAsRead(String recipientId) async {
    if (recipientId.isEmpty) return;
    try {
      await _client.from(recipientsTable).update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      }).eq('id', recipientId);
    } catch (_) {}
  }

  static Future<void> markAllAsRead(String userId) async {
    if (userId.isEmpty) return;
    try {
      await _client.from(recipientsTable).update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      }).eq('user_id', userId).eq('is_read', false);
    } catch (_) {}
  }

  // -- writes (event + fan-out) -------------------------------------------------

  /// Creates the event row, or reuses the existing one with the same
  /// (type, related_id) — the duplicate-prevention guarantee. Re-saving
  /// the same attendance therefore never spawns a second notification;
  /// a changed message (e.g. Present → Absent) refreshes in place.
  static Future<String?> publishEvent({
    required String type,
    required String title,
    required String message,
    String? relatedId,
    String destination = destDashboard,
    String? audienceType,
    String? section,
    DateTime? expiresAt,
  }) async {
    try {
      if (relatedId != null && relatedId.isNotEmpty) {
        try {
          final existing = await _client
              .from(eventsTable)
              .select('id,title,message')
              .eq('type', type)
              .eq('related_id', relatedId)
              .limit(1);
          final list = List<Map<String, dynamic>>.from(existing);
          if (list.isNotEmpty) {
            final row = list.first;
            final id = (row['id'] ?? '').toString();
            if ((row['title'] ?? '') != title ||
                (row['message'] ?? '') != message) {
              try {
                await _client.from(eventsTable).update({
                  'title': title,
                  'message': message,
                }).eq('id', id);
              } catch (_) {}
            }
            return id.isEmpty ? null : id;
          }
        } catch (_) {}
      }
      final payload = <String, dynamic>{
        'type': type,
        'title': title,
        'message': message,
        'destination': destination,
      };
      if (relatedId != null && relatedId.isNotEmpty) {
        payload['related_id'] = relatedId;
      }
      if (audienceType != null && audienceType.isNotEmpty) {
        payload['audience_type'] = audienceType;
      }
      if (section != null && section.isNotEmpty) {
        payload['section'] = section;
      }
      if (expiresAt != null) {
        payload['expires_at'] = expiresAt.toIso8601String();
      }
      final created = await _client
          .from(eventsTable)
          .insert(payload)
          .select('id')
          .single();
      final id = (created['id'] ?? '').toString();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// Fan-out: resolves WHO receives [notificationId] and inserts the
  /// recipient rows, skipping users that already have one (idempotent).
  static Future<void> fanOut({
    required String notificationId,
    String audience = audienceAll,
    String? section,
    String? userId,
    List<String> excludeUserIds = const [],
  }) async {
    if (notificationId.isEmpty) return;
    try {
      final targets = await resolveRecipients(
        audience: audience,
        section: section,
        userId: userId,
      );
      final excluded = excludeUserIds.toSet();
      final fresh =
          targets.where((u) => u.isNotEmpty && !excluded.contains(u)).toSet();
      if (fresh.isEmpty) return;

      Set<String> already = {};
      try {
        final rows = await _client
            .from(recipientsTable)
            .select('user_id')
            .eq('notification_id', notificationId)
            .inFilter('user_id', fresh.toList());
        already = {
          for (final r in (rows as List)) (r as Map)['user_id'].toString(),
        };
      } catch (_) {}

      final missing = fresh.where((u) => !already.contains(u)).toList();
      if (missing.isEmpty) return;
      try {
        await _client.from(recipientsTable).insert([
          for (final u in missing)
            {'notification_id': notificationId, 'user_id': u},
        ]);
      } catch (_) {
        // Unique-index race: rows already exist = desired end state.
      }
    } catch (_) {}
  }

  /// One call for the common case: create-or-reuse the event, then fan out.
  static Future<void> publish({
    required String type,
    required String title,
    required String message,
    String? relatedId,
    String destination = destDashboard,
    String audience = audienceAll,
    String? section,
    String? userId,
    List<String> excludeUserIds = const [],
    DateTime? expiresAt,
  }) async {
    try {
      final id = await publishEvent(
        type: type,
        title: title,
        message: message,
        relatedId: relatedId,
        destination: destination,
        audienceType: audience,
        section: section,
        expiresAt: expiresAt,
      );
      if (id == null || id.isEmpty) return;
      await fanOut(
        notificationId: id,
        audience: audience,
        section: section,
        userId: userId,
        excludeUserIds: excludeUserIds,
      );
    } catch (_) {}
  }

  // -- recipient resolution -----------------------------------------------------

  static String normalizeSection(String? section) {
    final s = (section ?? '').trim().toLowerCase();
    if (s == 'sub junior' || s == 'sub-junior' || s == 'subjunior') {
      return 'sub-junior';
    }
    return s;
  }

  /// Resolves user ids for an audience. Sections use the EXISTING
  /// Sub Junior / Junior / Senior values — no new section system.
  static Future<Set<String>> resolveRecipients({
    String audience = audienceAll,
    String? section,
    String? userId,
  }) async {
    final out = <String>{};
    final sec = normalizeSection(section);
    try {
      switch (audience) {
        case audienceIndividual:
          if (userId != null && userId.isNotEmpty) out.add(userId);
          break;
        case audienceStudents:
          out.addAll(await _idsOf('students', section: sec));
          break;
        case audienceTeachers:
          out.addAll(await _idsOf('teachers', section: sec));
          break;
        case audienceAdmins:
          out.addAll(await _idsOf('admin', section: null));
          break;
        case audienceSection:
          if (sec.isNotEmpty) {
            out.addAll(await _idsOf('students', section: sec));
            out.addAll(await _idsOf('teachers', section: sec));
          }
          break;
        default: // all
          out.addAll(await _idsOf('students', section: sec.isEmpty ? null : sec));
          out.addAll(await _idsOf('teachers', section: sec.isEmpty ? null : sec));
          if (sec.isEmpty) out.addAll(await _idsOf('admin', section: null));
      }
    } catch (_) {}
    return out;
  }

  static Future<List<String>> _idsOf(String table, {String? section}) async {
    try {
      var query = _client.from(table).select('id');
      if (section != null && section.isNotEmpty) {
        query = query.eq('section', section);
      }
      final rows = await query;
      return [
        for (final r in (rows as List))
          ((r as Map)['id'] ?? '').toString(),
      ].where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  // -- convenience emitters (important user-facing events ONLY) ------------------

  static String prettyStatus(String? status) {
    final s = (status ?? '').trim().toLowerCase();
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  /// Teacher marked a student's attendance → that student.
  static Future<void> attendanceMarked({
    required String studentId,
    required String status,
    required String section,
    required String date,
    String? reportId,
  }) {
    final label = prettyStatus(status);
    final ref = (reportId != null && reportId.isNotEmpty)
        ? 'attendance_report:$reportId:$studentId'
        : 'attendance:${normalizeSection(section)}:$date:$studentId';
    return publish(
      type: typeAttendance,
      title: 'Attendance Marked',
      message: 'Your attendance has been marked as $label.',
      relatedId: ref,
      destination: destAttendance,
      audience: audienceIndividual,
      userId: studentId,
      section: normalizeSection(section),
    );
  }

  /// Admin marked a teacher's attendance → that teacher.
  static Future<void> teacherAttendanceMarked({
    required String teacherId,
    required String status,
    required String date,
  }) {
    final label = prettyStatus(status);
    return publish(
      type: typeAttendance,
      title: 'Attendance Updated',
      message: 'Your attendance has been marked as $label.',
      relatedId: 'teacher_attendance:$date:$teacherId',
      destination: destMyAttendance,
      audience: audienceIndividual,
      userId: teacherId,
    );
  }

  /// Teacher sent an attendance report → admins.
  static Future<void> attendanceReportSent({
    required String reportId,
    required String section,
    required String date,
  }) {
    final sec = normalizeSection(section);
    final label = sec.isEmpty
        ? date
        : '${sec[0].toUpperCase()}${sec.substring(1)} · $date';
    return publish(
      type: typeAttendance,
      title: 'New Attendance Report',
      message: 'A new student attendance report has been submitted ($label).',
      relatedId: 'attendance_report:$reportId',
      destination: destStudentReports,
      audience: audienceAdmins,
    );
  }

  /// Admin published a notice → its audience (students / teachers / all).
  static Future<void> noticePublished({
    required String noticeId,
    required String noticeTitle,
    required String audience,
  }) {
    final a = audience.trim().toLowerCase();
    final resolved = a == 'teacher' || a == 'teachers'
        ? audienceTeachers
        : a == 'student' || a == 'students'
            ? audienceStudents
            : audienceAll;
    return publish(
      type: typeNotice,
      title: 'New Notice',
      message: noticeTitle.trim().isEmpty
          ? 'A new notice has been published.'
          : 'A new notice "$noticeTitle" has been published.',
      relatedId: 'notice:$noticeId',
      destination: destNoticeBoard,
      audience: resolved,
    );
  }

  /// Student submitted a leave application → admins + self confirmation.
  static Future<void> leaveSubmitted({
    required String applicationId,
    required String studentId,
    required String studentName,
  }) async {
    try {
      await publish(
        type: typeLeave,
        title: 'New Leave Application',
        message: studentName.trim().isEmpty
            ? 'A new student leave application has been submitted.'
            : 'A new student leave application has been submitted by $studentName.',
        relatedId: 'leave:$applicationId',
        destination: destLeaveApplication,
        audience: audienceAdmins,
      );
    } catch (_) {}
    try {
      await publish(
        type: typeLeave,
        title: 'Leave Application Submitted',
        message:
            'Your leave application has been submitted. Please wait for Admin approval.',
        relatedId: 'leave:$applicationId:self',
        destination: destLeaveApplication,
        audience: audienceIndividual,
        userId: studentId,
      );
    } catch (_) {}
  }

  /// Admin approved / rejected a leave application → the student.
  static Future<void> leaveDecided({
    required String applicationId,
    required String studentId,
    required bool approved,
  }) {
    return publish(
      type: typeLeave,
      title: approved
          ? 'Leave Application Approved'
          : 'Leave Application Rejected',
      message: approved
          ? 'Your leave application has been successfully approved by Admin.'
          : 'Your leave application has been rejected by Admin.',
      relatedId: 'leave:$applicationId:decision',
      destination: destLeaveApplication,
      audience: audienceIndividual,
      userId: studentId,
    );
  }

  /// Admin pressed "Send to Teacher" → teachers of the section.
  static Future<void> leaveSentToTeacher({
    required String applicationId,
    required String section,
  }) {
    return publish(
      type: typeStudentApplication,
      title: 'New Student Application',
      message:
          'A new approved student leave application has been sent to you.',
      relatedId: 'leave:$applicationId:sent',
      destination: destStudentApplications,
      audience: audienceTeachers,
      section: normalizeSection(section),
    );
  }

  /// Admin published a lesson plan → students + teachers of the section.
  static Future<void> lessonPlanPublished({
    required String lessonId,
    required String section,
  }) {
    return publish(
      type: typeLessonPlan,
      title: 'New Lesson Plan',
      message: 'A new lesson plan has been published for your section.',
      relatedId: 'lesson_plan:$lessonId',
      destination: destLessonPlan,
      audience: audienceSection,
      section: normalizeSection(section),
    );
  }

  /// Teacher added a memory verse → students of the section.
  static Future<void> memoryVerseAdded({
    required String verseId,
    required String section,
  }) {
    return publish(
      type: typeMemoryVerse,
      title: 'New Memory Verse',
      message: 'A new memory verse has been added for your section.',
      relatedId: 'memory_verse:$verseId',
      destination: destMemoryVerse,
      audience: audienceStudents,
      section: normalizeSection(section),
    );
  }

  /// Teacher updated a student's recitation status → that student.
  static Future<void> recitationUpdated({
    required String studentId,
    required String verseId,
    required String status,
    String? section,
  }) {
    final label = prettyStatus(status).replaceAll('_', ' ');
    return publish(
      type: typeMemoryVerse,
      title: 'Memory Verse Updated',
      message: label.isEmpty
          ? 'Your memory verse recitation status has been updated.'
          : 'Your memory verse recitation status has been updated to $label.',
      relatedId: 'recitation:$verseId:$studentId',
      destination: destMemoryVerse,
      audience: audienceIndividual,
      userId: studentId,
      section: section == null ? null : normalizeSection(section),
    );
  }

  /// User submitted a credential-change request → admins.
  static Future<void> credentialRequestSubmitted({
    required String requestId,
    required String role,
    required String fullName,
  }) {
    final who = fullName.trim().isEmpty
        ? (role.trim().toLowerCase() == 'teacher' ? 'A Teacher' : 'A Student')
        : fullName.trim();
    return publish(
      type: typeAuthentication,
      title: 'New Credential Change Request',
      message: '$who has submitted a credential change request.',
      relatedId: 'credential:$requestId',
      destination: destCredentialsAdmin,
      audience: audienceAdmins,
    );
  }

  /// Admin approved / rejected a credential-change request → the user.
  static Future<void> credentialRequestDecided({
    required String requestId,
    required String userId,
    required bool approved,
  }) {
    return publish(
      type: typeAuthentication,
      title: approved
          ? 'Credential Change Approved'
          : 'Credential Change Rejected',
      message: approved
          ? 'Admin has successfully approved your credential change request.'
          : 'Your credential change request has been rejected by Admin.',
      relatedId: 'credential:$requestId:decision',
      destination: destCredentials,
      audience: audienceIndividual,
      userId: userId,
    );
  }

  /// User submitted a password-reset request → admins.
  static Future<void> passwordResetRequested({
    required String requestId,
    required String fullName,
  }) {
    final who = fullName.trim().isEmpty ? 'Someone' : fullName.trim();
    return publish(
      type: typeAuthentication,
      title: 'New Password Reset Request',
      message: '$who has submitted a password reset request.',
      relatedId: 'password_reset:$requestId',
      destination: destPasswordResetAdmin,
      audience: audienceAdmins,
    );
  }

  /// Admin approved / rejected a password-reset request → the user.
  static Future<void> passwordResetDecided({
    required String requestId,
    required String userId,
    required bool approved,
  }) {
    return publish(
      type: typeAuthentication,
      title: approved ? 'Password Reset Approved' : 'Password Reset Rejected',
      message: approved
          ? 'Your password reset request has been approved. Please complete the next step within 30 minutes.'
          : 'Your password reset request has been rejected by Admin.',
      relatedId: 'password_reset:$requestId:decision',
      destination: destCredentials,
      audience: audienceIndividual,
      userId: userId,
    );
  }

  /// Admin added a Download Center resource → its audience.
  static Future<void> downloadPublished({
    required String itemId,
    required String title,
    required String audience,
  }) {
    final a = audience.trim().toLowerCase();
    final resolved = a == 'teacher' || a == 'teachers'
        ? audienceTeachers
        : a == 'student' || a == 'students'
            ? audienceStudents
            : audienceAll;
    return publish(
      type: typeDownload,
      title: 'New Resource Available',
      message: title.trim().isEmpty
          ? 'A new resource has been added to the Download Center.'
          : 'A new resource "$title" has been added to the Download Center.',
      relatedId: 'download:$itemId',
      destination: destDownloadCenter,
      audience: resolved,
    );
  }

  /// Admin website-update message → audience (uses the existing update
  /// flow; no duplicate update functionality is created).
  static Future<void> websiteUpdate({
    required String updateId,
    String audience = audienceAll,
    String? section,
  }) {
    return publish(
      type: typeWebsiteUpdate,
      title: 'Website Update Available',
      message: 'A new website update is available.',
      relatedId: 'website_update:$updateId',
      destination: destDashboard,
      audience: audience,
      section: section,
    );
  }

  // -- retention ---------------------------------------------------------------

  /// Recovers the id of a row that was JUST inserted, when the
  /// `insert().select().single()` round-trip fails after the row was
  /// already created (e.g. a representation hiccup). Returns '' unless
  /// the newest matching row was created within [withinMinutes] — so a
  /// stale row can never be mistaken for the new one. Used INSTEAD of
  /// re-inserting (which would duplicate the application/notice/verse).
  static Future<String> recoverNewestId({
    required String table,
    required Map<String, String> match,
    String orderBy = 'created_at',
    int withinMinutes = 5,
  }) async {
    try {
      var query = _client.from(table).select('id,$orderBy');
      match.forEach((k, v) {
        query = query.eq(k, v);
      });
      final rows =
          await query.order(orderBy, ascending: false).limit(1);
      final list = List<Map<String, dynamic>>.from(rows);
      if (list.isEmpty) return '';
      final created =
          DateTime.tryParse((list.first[orderBy] ?? '').toString());
      if (created == null ||
          DateTime.now().difference(created).inMinutes.abs() >
              withinMinutes) {
        return '';
      }
      return (list.first['id'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  /// Moves notifications older than [_archiveRetentionDays] into
  /// notification_archive via the `archive_old_notifications` RPC.
  /// Runs at most once per day per device; failures are ignored.
  static Future<void> archiveOldIfDue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_archiveLastRunKey) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - last < const Duration(hours: 24).inMilliseconds) return;
      await prefs.setInt(_archiveLastRunKey, nowMs);
      try {
        await _client.rpc('archive_old_notifications',
            params: {'days': _archiveRetentionDays});
      } catch (_) {}
    } catch (_) {}
  }

  // -- time labels ---------------------------------------------------------------

  static const _shortMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'
  ];

  /// Just now · 5 minutes ago · 3 hours ago · Yesterday · Sept 5.
  static String timeAgo(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m minute${m == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24 && now.day == date.day) {
      final h = diff.inHours;
      return '$h hour${h == 1 ? '' : 's'} ago';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    }
    final base = '${_shortMonths[date.month - 1]} ${date.day}';
    return date.year == now.year ? base : '$base, ${date.year}';
  }

  /// Today · Yesterday · Sept 5 (group headers in the panel).
  static String dayGroup(DateTime? date) {
    if (date == null) return 'Earlier';
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    }
    final base = '${_shortMonths[date.month - 1]} ${date.day}';
    return date.year == now.year ? base : '$base, ${date.year}';
  }
}

/// One notification addressed to the current user: the event fields from
/// `notifications` plus this user's read state from
/// `notification_recipients`.
class AppNotification {
  final String recipientId;
  final String notificationId;
  final String type;
  final String title;
  final String message;
  final String? relatedId;
  final String destination;
  final String? audienceType;
  final String? section;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  const AppNotification({
    required this.recipientId,
    required this.notificationId,
    required this.type,
    required this.title,
    required this.message,
    this.relatedId,
    required this.destination,
    this.audienceType,
    this.section,
    required this.isRead,
    this.readAt,
    this.createdAt,
    this.expiresAt,
  });

  bool get isExpired {
    if (expiresAt == null) return false;
    return expiresAt!.isBefore(DateTime.now());
  }

  String get timeLabel => NotificationService.timeAgo(createdAt?.toLocal());

  static DateTime? _parse(dynamic raw) {
    if (raw == null) return null;
    final src = raw.toString().trim();
    if (src.isEmpty) return null;
    try {
      return DateTime.parse(src).toLocal();
    } catch (_) {
      return null;
    }
  }

  /// From the embedded-select row
  /// (`... notification_recipients + notifications(*) `).
  static AppNotification? fromJoined(Map<String, dynamic> row) {
    final rawEvent = row['notifications'];
    Map<String, dynamic>? event;
    if (rawEvent is Map) {
      event = Map<String, dynamic>.from(rawEvent);
    } else if (rawEvent is List && rawEvent.isNotEmpty) {
      event = Map<String, dynamic>.from(rawEvent.first as Map);
    }
    if (event == null) return null;
    return fromParts(row, event);
  }

  static AppNotification fromParts(
    Map<String, dynamic> recipient,
    Map<String, dynamic> event,
  ) {
    return AppNotification(
      recipientId: (recipient['id'] ?? '').toString(),
      notificationId: (event['id'] ?? recipient['notification_id'] ?? '').toString(),
      type: (event['type'] ?? '').toString(),
      title: (event['title'] ?? 'Notification').toString(),
      message: (event['message'] ?? '').toString(),
      relatedId: event['related_id']?.toString(),
      destination:
          (event['destination'] ?? NotificationService.destDashboard).toString(),
      audienceType: event['audience_type']?.toString(),
      section: event['section']?.toString(),
      isRead: recipient['is_read'] == true,
      readAt: _parse(recipient['read_at']),
      createdAt: _parse(event['created_at'] ?? recipient['created_at']),
      expiresAt: _parse(event['expires_at']),
    );
  }
}
