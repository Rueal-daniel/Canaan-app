import 'package:supabase_flutter/supabase_flutter.dart';

import 'leaderboard_service.dart';
import 'leave_service.dart';
import 'notification_service.dart';

/// Student Achievement Certificates — issued ONLY by Admin for real
/// Leaderboard Rank 1/2/3 finishes (Attendance / Memory Verse).
///
/// LIFECYCLE:
///   draft → (Admin publishes) → published. Students and teachers can
///   ONLY ever read published rows scoped to themselves (§4, §13); drafts
///   are invisible outside the Admin page. Publishing fans out a
///   "New Certificate Available" notification (drafts never notify).
///
/// HISTORICAL ACCURACY (§15): the certificate snapshots name, section,
/// category, position and percentage at issue time. Later leaderboard
/// changes NEVER mutate a published certificate — nothing is
/// auto-generated or auto-updated.
///
/// ELIGIBILITY (§2, §14): [verifyEligibility] recomputes the LIVE
/// leaderboard and requires the student's CURRENT rank to equal the
/// requested position (1–3). A Rank 5 student can never receive a
/// "1st Position" certificate.
///
/// SECURITY (§13 — enforced here, not just in Flutter UI):
///   • Admin methods take no trust from the UI beyond ids; eligibility is
///     always re-verified against live data at save time.
///   • [publishedForStudent] filters by the VERIFIED active student id +
///     status='published' server-side — a forged id returns nothing.
///   • [publishedForSection] filters by the teacher's SERVER-RESOLVED
///     section + status='published' — no section parameter to tamper with.
///   • Only certificate-safe columns are stored/selected — never
///     passwords or private family information.
class CertificateService {
  static SupabaseClient get _client => Supabase.instance.client;

  static const table = 'certificates';

  static const categoryAttendance = 'attendance';
  static const categoryMemoryVerse = 'memory_verse';

  static const statusDraft = 'draft';
  static const statusPublished = 'published';

  static String normalizeCategory(String? category) {
    final c = (category ?? '').trim().toLowerCase();
    if (c == categoryMemoryVerse ||
        c == 'memory' ||
        c == 'memory verse' ||
        c == 'memory_verse_recitation' ||
        c == 'memory verse recitation') {
      return categoryMemoryVerse;
    }
    return categoryAttendance;
  }

  static String categoryLabel(String? category) {
    return normalizeCategory(category) == categoryMemoryVerse
        ? 'Memory Verse Recitation'
        : 'Attendance';
  }

  static String positionLabel(int position) {
    switch (position) {
      case 1:
        return '1st Position';
      case 2:
        return '2nd Position';
      case 3:
        return '3rd Position';
      default:
        return 'Position $position';
    }
  }

  static String prettySection(String? section) =>
      LeaderboardService.prettySection(section);

  static String normalizeSection(String? section) =>
      LeaveService.normalizeSection(section);

  static String todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String prettyDate(String? raw) {
    final src = (raw ?? '').trim();
    if (src.isEmpty) return '';
    try {
      final d = DateTime.parse(src).toLocal();
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return src.split('T').first;
    }
  }

  // -- eligibility (live leaderboard check) ----------------------------------

  /// The student's CURRENT rank on the live board, or 0 when unranked /
  /// outside the board (no records, suspended, deleted, wrong section).
  static Future<int> liveRankOf({
    required String studentId,
    required String section,
    required String category,
  }) async {
    final sid = studentId.trim();
    final sec = normalizeSection(section);
    if (sid.isEmpty || sec.isEmpty) return 0;
    try {
      final entries = await LeaderboardService.compute(
        section: sec,
        memory: normalizeCategory(category) == categoryMemoryVerse,
      );
      for (final e in entries) {
        if (e.studentId == sid) return e.rank; // 0 when unranked
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// True only when the student CURRENTLY holds [position] (1–3) on the
  /// live board for [section] + [category].
  static Future<bool> verifyEligibility({
    required String studentId,
    required String section,
    required String category,
    required int position,
  }) async {
    if (position < 1 || position > 3) return false;
    final rank = await liveRankOf(
      studentId: studentId,
      section: section,
      category: category,
    );
    return rank == position;
  }

  // -- admin: create / edit / publish / delete ---------------------------------

  /// Creates a DRAFT after re-verifying eligibility against the LIVE
  /// leaderboard. Returns the new row id, or '' when not eligible.
  /// [certificateDate] defaults to today (`yyyy-MM-dd`).
  static Future<String> createDraft({
    required String studentId,
    required String studentName,
    required String section,
    required String category,
    required int position,
    required double percentage,
    required String adminId,
    String certificateDate = '',
  }) async {
    final eligible = await verifyEligibility(
      studentId: studentId,
      section: section,
      category: category,
      position: position,
    );
    if (!eligible) return '';
    try {
      final now = DateTime.now().toIso8601String();
      final created = await _client
          .from(table)
          .insert({
            'student_id': studentId.trim(),
            'student_name': studentName.trim(),
            'section': normalizeSection(section),
            'category': normalizeCategory(category),
            'position': position,
            'percentage': percentage,
            'certificate_date':
                certificateDate.trim().isEmpty ? todayStr() : certificateDate.trim(),
            'status': statusDraft,
            'generated_by': adminId.trim(),
            'created_at': now,
            'updated_at': now,
          })
          .select('id')
          .single();
      return (created['id'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  /// Edits a DRAFT (position re-verified against the live board; date
  /// editable). Published certificates are locked for historical
  /// accuracy — unpublish to draft first.
  static Future<bool> updateDraft({
    required String certificateId,
    required int position,
    required String certificateDate,
  }) async {
    try {
      final row = await _client
          .from(table)
          .select('student_id, section, category, status')
          .eq('id', certificateId.trim())
          .maybeSingle();
      if (row == null || (row['status'] ?? '') != statusDraft) return false;
      final eligible = await verifyEligibility(
        studentId: (row['student_id'] ?? '').toString(),
        section: (row['section'] ?? '').toString(),
        category: (row['category'] ?? '').toString(),
        position: position,
      );
      if (!eligible) return false;
      await _client.from(table).update({
        'position': position,
        'certificate_date': certificateDate.trim().isEmpty
            ? todayStr()
            : certificateDate.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', certificateId.trim());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Publishes a draft: flips status, stamps published_at, and notifies
  /// the student (+ section teachers). Only then does it become visible
  /// outside the Admin page (§4). Returns false when the row is missing.
  static Future<bool> publish(String certificateId) async {
    try {
      final row = await _client
          .from(table)
          .select('*')
          .eq('id', certificateId.trim())
          .maybeSingle();
      if (row == null) return false;
      if ((row['status'] ?? '') == statusPublished) return true;
      await _client.from(table).update({
        'status': statusPublished,
        'published_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', certificateId.trim());
      // Notify (fire-and-forget — publishing never fails because of this).
      try {
        await NotificationService.certificatePublished(
          certificateId: (row['id'] ?? '').toString(),
          studentId: (row['student_id'] ?? '').toString(),
          studentName: (row['student_name'] ?? '').toString(),
          section: (row['section'] ?? '').toString(),
          category: (row['category'] ?? '').toString(),
          position: (row['position'] as num?)?.toInt() ?? 0,
        );
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sends a published certificate back to draft (hides it from student
  /// and teacher pages again). No notification is sent.
  static Future<bool> unpublish(String certificateId) async {
    try {
      await _client.from(table).update({
        'status': statusDraft,
        'published_at': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', certificateId.trim());
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> delete(String certificateId) async {
    try {
      await _client.from(table).delete().eq('id', certificateId.trim());
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchAll() async {
    try {
      final rows = await _client
          .from(table)
          .select('*')
          .order('created_at', ascending: false);
      return [for (final r in (rows as List)) Map<String, dynamic>.from(r as Map)];
    } catch (_) {
      return [];
    }
  }

  // -- scoped reads (student / teacher — published only) -----------------------

  /// Published certificates for ONE verified student id, newest first.
  /// A forged id simply matches nothing (§13).
  static Future<List<Map<String, dynamic>>> publishedForStudent(
    String studentId,
  ) async {
    final sid = studentId.trim();
    if (sid.isEmpty) return [];
    try {
      final rows = await _client
          .from(table)
          .select('*')
          .eq('student_id', sid)
          .eq('status', statusPublished)
          .order('created_at', ascending: false);
      return [for (final r in (rows as List)) Map<String, dynamic>.from(r as Map)];
    } catch (_) {
      return [];
    }
  }

  /// Published certificates for a whole section (teacher view), newest
  /// first. Callers pass the SERVER-RESOLVED section only.
  static Future<List<Map<String, dynamic>>> publishedForSection(
    String section,
  ) async {
    final sec = normalizeSection(section);
    if (sec.isEmpty) return [];
    try {
      final rows = await _client
          .from(table)
          .select('*')
          .eq('section', sec)
          .eq('status', statusPublished)
          .order('created_at', ascending: false);
      return [for (final r in (rows as List)) Map<String, dynamic>.from(r as Map)];
    } catch (_) {
      return [];
    }
  }
}
