import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared attendance-report workflow logic (teacher + admin).
///
/// Report lifecycle in `attendance_reports.status`:
///   `submitted` → saved by teacher, not sent yet
///   `pending`   → sent, "Pending Admin Review"
///   `approved`  → approved by admin
///   `rejected`  → rejected by admin (see `rejection_reason`)
///
/// Review metadata columns (`rejection_reason`, `reviewed_by_admin_id`,
/// `reviewed_at`) are written resiliently: if the migration adding them
/// has not been run yet, the update is retried with just the `status`
/// so the core flow keeps working.
class AttendanceReportService {
  static const submitted = 'submitted';
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';

  static const _metaKeys = {
    'rejection_reason',
    'reviewed_by_admin_id',
    'reviewed_at',
  };

  static String norm(String? status) => (status ?? '').trim().toLowerCase();

  static String label(String? status) {
    switch (norm(status)) {
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
        return s.isEmpty ? 'Saved' : s;
    }
  }

  static Color color(String? status) {
    switch (norm(status)) {
      case pending:
        return const Color(0xFFF59E0B);
      case approved:
        return const Color(0xFF22C55E);
      case rejected:
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF6366F1);
    }
  }

  static String _now() => DateTime.now().toIso8601String();

  /// Updates a report, retrying without review-metadata columns if the
  /// migration has not been applied yet.
  static Future<void> updateReport(
    SupabaseClient client,
    int id,
    Map<String, dynamic> payload,
  ) async {
    try {
      await client.from('attendance_reports').update(payload).eq('id', id);
    } catch (_) {
      final fallback = Map<String, dynamic>.from(payload)
        ..removeWhere((k, _) => _metaKeys.contains(k));
      await client.from('attendance_reports').update(fallback).eq('id', id);
    }
  }

  /// Teacher sends a saved report for admin review (fresh review cycle).
  static Future<void> sendReport(SupabaseClient client, int reportId) {
    return updateReport(client, reportId, {
      'status': pending,
      'rejection_reason': null,
      'reviewed_by_admin_id': null,
      'reviewed_at': null,
      'updated_at': _now(),
    });
  }

  /// Admin approves a pending report.
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
      'updated_at': _now(),
    });
  }

  /// Admin rejects a pending report with a mandatory reason.
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
      'updated_at': _now(),
    });
  }
}
