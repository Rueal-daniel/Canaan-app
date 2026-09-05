import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared memory-verse recitation workflow logic.
///
/// Per-section recitation tables (`recitation_sub_junior`,
/// `recitation_junior`, `recitation_senior`) hold one row per
/// student + verse: `{student_id, student_name, verse_id,
/// teacher_id, status, date}`.
///
/// `memory_verse_reports` holds the sent report per verse + teacher
/// + date with embedded `student_details` and counts. Lifecycle:
///   `submitted` → saved, not sent · `pending` → Pending Admin Review
///   `approved` / `rejected` (see `rejection_reason`).
class RecitationService {
  static const recited = 'recited';
  static const halfRecited = 'half_recited';
  static const notRecited = 'not_recited';

  static const submitted = 'submitted';
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';

  /// Columns that may not exist until the migration is run.
  static const _reportMetaKeys = {
    'half_recited_count',
    'rejection_reason',
    'reviewed_by_admin_id',
    'reviewed_at',
  };

  static String? sectionTable(String section) {
    switch (section) {
      case 'sub-junior':
        return 'recitation_sub_junior';
      case 'junior':
        return 'recitation_junior';
      case 'senior':
        return 'recitation_senior';
      default:
        return null;
    }
  }

  static String norm(String? status) => (status ?? '').trim().toLowerCase();

  static bool isKnownRecitation(String? status) {
    final s = norm(status);
    return s == recited || s == halfRecited || s == notRecited;
  }

  static String label(String? status) {
    switch (norm(status)) {
      case recited:
        return 'Recited';
      case halfRecited:
        return 'Half Recited';
      case notRecited:
        return 'Not Recited';
      case pending:
        return 'Pending Admin Review';
      case approved:
        return 'Approved';
      case rejected:
        return 'Rejected';
      case submitted:
        return 'Saved';
      default:
        final s = (status ?? '').trim();
        return s.isEmpty ? '—' : s;
    }
  }

  static Color color(String? status) {
    switch (norm(status)) {
      case recited:
      case approved:
        return const Color(0xFF22C55E);
      case halfRecited:
      case pending:
        return const Color(0xFFF59E0B);
      case notRecited:
      case rejected:
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF6366F1);
    }
  }

  static String todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Saturday-only marking (Sunday School operates on Saturday).
  /// Set to false to temporarily allow marking on any day.
  static const enforceSaturdayOnly = true;
  static bool get isSaturday =>
      DateTime.now().weekday == DateTime.saturday;
  static bool get markingAllowed =>
      !enforceSaturdayOnly || isSaturday;

  static String prettyDate(String? raw) {
    final src = (raw ?? '').trim();
    if (src.isEmpty) return '';
    try {
      final d = DateTime.parse(src).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return src.split('T').first;
    }
  }

  static String _now() => DateTime.now().toIso8601String();

  /// Updates a verse report, retrying without newer columns when the
  /// migration adding them has not been run yet.
  static Future<void> updateReport(
    SupabaseClient client,
    int id,
    Map<String, dynamic> payload,
  ) async {
    try {
      await client.from('memory_verse_reports').update(payload).eq('id', id);
    } catch (_) {
      final fallback = Map<String, dynamic>.from(payload)
        ..removeWhere((k, _) => _reportMetaKeys.contains(k));
      await client.from('memory_verse_reports').update(fallback).eq('id', id);
    }
  }

  /// Finds today's report for this verse + teacher (dedupe key).
  static Future<Map<String, dynamic>?> findTodaysReport(
    SupabaseClient client, {
    required int verseId,
    required String teacherId,
    required String date,
  }) async {
    var query = client
        .from('memory_verse_reports')
        .select('*')
        .eq('verse_id', verseId.toString())
        .eq('date', date);
    if (teacherId.isNotEmpty) {
      query = query.eq('teacher_id', teacherId);
    }
    final rows = await query.limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    return list.isEmpty ? null : list.first;
  }

  /// Teacher sends a saved report for admin review (fresh review cycle).
  static Future<void> sendReport(
    SupabaseClient client,
    int reportId,
    Map<String, dynamic> payload,
  ) {
    return updateReport(client, reportId, {
      ...payload,
      'status': pending,
      'rejection_reason': null,
      'reviewed_by_admin_id': null,
      'reviewed_at': null,
    });
  }

  static Future<void> approveReport(
    SupabaseClient client,
    int reportId,
    String adminId,
  ) {
    return updateReport(client, reportId, {
      'status': approved,
      'rejection_reason': null,
      'reviewed_by_admin_id': adminId.isEmpty ? null : adminId,
      'reviewed_at': _now(),
    });
  }

  static Future<void> rejectReport(
    SupabaseClient client,
    int reportId,
    String adminId,
    String reason,
  ) {
    return updateReport(client, reportId, {
      'status': rejected,
      'rejection_reason': reason,
      'reviewed_by_admin_id': adminId.isEmpty ? null : adminId,
      'reviewed_at': _now(),
    });
  }
}
