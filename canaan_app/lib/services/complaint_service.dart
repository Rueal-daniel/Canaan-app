import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';

/// Complaint / Problem Report system.
///
/// PUBLIC PATH (no login): [submit] inserts ONE row with the required
/// fields only. It never reads, lists, edits or deletes — anonymous
/// users cannot see other complaints, admin comments, or personal data.
///
/// ADMIN PATH (Admin-only screens): list / details / approve / reject
/// (+ comment) / delete.
///
/// SPAM PROTECTION (layered, not frontend-only):
///   • DB CHECK constraints (type/status/role whitelists, description
///     cap, phone format) — enforced by Supabase itself.
///   • Client cooldown: one submission per [cooldownMinutes] per device.
///   • Phone + length validation before the request is even sent.
///
/// STATUS NOTIFICATIONS (§16): deliberately NOT sent to the reporter —
/// a pre-login complaint carries no SECURE account association, and the
/// system never guesses identity from a typed name/phone number. Admins
/// ARE notified of every new complaint via the existing bell system.
class ComplaintService {
  static SupabaseClient get _client => Supabase.instance.client;

  static const table = 'complaints';

  static const roleTeacher = 'teacher';
  static const roleStudent = 'student';

  static const typeEmergency = 'emergency';
  static const typeReminder = 'reminder';

  static const statusPending = 'pending';
  static const statusApproved = 'approved';
  static const statusRejected = 'rejected';

  static const maxDescriptionLength = 1000;
  static const cooldownMinutes = 5;
  static const _cooldownKey = 'canaan_complaint_last_submit_ms';

  static String normalizeRole(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    return r == roleTeacher ? roleTeacher : roleStudent;
  }

  static String normalizeType(String? type) {
    final t = (type ?? '').trim().toLowerCase();
    return t == typeEmergency ? typeEmergency : typeReminder;
  }

  /// Phone must be 7–20 chars of digits, spaces, +, (), -, . (mirrors
  /// the DB CHECK so violations are caught before the round trip).
  static bool isValidPhone(String? phone) {
    final p = (phone ?? '').trim();
    if (p.length < 7 || p.length > 20) return false;
    return RegExp(r'^[0-9+()\-.\s]+$').hasMatch(p) &&
        RegExp(r'\d').hasMatch(p);
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

  // -- public submission (no login) --------------------------------------------

  /// Seconds remaining on the device cooldown (0 = may submit now).
  static Future<int> cooldownRemainingSeconds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_cooldownKey) ?? 0;
      if (last <= 0) return 0;
      final elapsed =
          DateTime.now().millisecondsSinceEpoch - last;
      final remaining =
          cooldownMinutes * 60 - elapsed ~/ 1000;
      return remaining > 0 ? remaining : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Submits a complaint. Returns '' on success, otherwise an error key:
  /// 'cooldown', 'validation', 'connection'.
  static Future<String> submit({
    required String role,
    required String fullName,
    required String phoneNumber,
    required String complaintType,
    required String description,
  }) async {
    final name = fullName.trim();
    final phone = phoneNumber.trim();
    final desc = description.trim();
    if (name.isEmpty ||
        name.length > 120 ||
        !isValidPhone(phone) ||
        desc.isEmpty ||
        desc.length > maxDescriptionLength) {
      return 'validation';
    }
    final wait = await cooldownRemainingSeconds();
    if (wait > 0) return 'cooldown:$wait';
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final created = await _client
          .from(table)
          .insert({
            'role': normalizeRole(role),
            'full_name': name,
            'phone_number': phone,
            'complaint_type': normalizeType(complaintType),
            'description': desc,
            'status': statusPending,
            'created_at': now,
            'updated_at': now,
          })
          .select('id,role,full_name,complaint_type')
          .single();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
            _cooldownKey, DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}
      // Admin bell notification (fire-and-forget).
      try {
        await NotificationService.complaintSubmitted(
          complaintId: (created['id'] ?? '').toString(),
          reporterName: (created['full_name'] ?? '').toString(),
          role: (created['role'] ?? '').toString(),
          complaintType:
              (created['complaint_type'] ?? '').toString(),
        );
      } catch (_) {}
      return '';
    } catch (_) {
      return 'connection';
    }
  }

  // -- admin ----------------------------------------------------------------------

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

  static Future<int> pendingCount() async {
    try {
      final rows = await _client
          .from(table)
          .select('id')
          .eq('status', statusPending);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> approve({
    required String complaintId,
    String adminComment = '',
    String adminId = '',
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final payload = <String, dynamic>{
        'status': statusApproved,
        'admin_comment': adminComment.trim(),
        'reviewed_at': now,
        'updated_at': now,
      };
      if (adminId.trim().isNotEmpty) {
        payload['reviewed_by'] = adminId.trim();
      }
      await _client
          .from(table)
          .update(payload)
          .eq('id', complaintId.trim());
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> reject({
    required String complaintId,
    String reason = '',
    String adminId = '',
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final payload = <String, dynamic>{
        'status': statusRejected,
        'rejection_reason': reason.trim(),
        'reviewed_at': now,
        'updated_at': now,
      };
      if (adminId.trim().isNotEmpty) {
        payload['reviewed_by'] = adminId.trim();
      }
      await _client
          .from(table)
          .update(payload)
          .eq('id', complaintId.trim());
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> remove(String complaintId) async {
    try {
      await _client
          .from(table)
          .delete()
          .eq('id', complaintId.trim());
      return true;
    } catch (_) {
      return false;
    }
  }
}
