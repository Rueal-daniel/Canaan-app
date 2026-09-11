import 'package:supabase_flutter/supabase_flutter.dart';

import 'language_service.dart';

/// Digital Student ID Card data layer.
///
/// The existing `students` row is the single source of truth
/// (full_name, section, photo_url, ...). The ONLY ID-card-specific
/// column is `students.student_id_number` (e.g. C-1024 — see
/// `supabase/student_ids.sql`): permanent, unique, never re-minted on
/// view. Only an explicit Admin (re-)generate changes it.
class StudentIdService {
  static SupabaseClient get _client => Supabase.instance.client;

  static const _bucket = 'student-photos';
  static const _storageBase =
      'https://pjytoxyddfrsrkzappbb.supabase.co/storage/v1/object/public';

  /// First number of the C-#### series (matches the C-1024 example).
  static const firstNumber = 1024;

  /// Public photo URL for a stored `photo_url` path, or '' when the
  /// student has no photo (callers show initials instead).
  static String photoUrl(String? path) {
    final p = (path ?? '').trim();
    if (p.isEmpty) return '';
    if (p.startsWith('http')) return p;
    return '$_storageBase/$_bucket/$p';
  }

  static String prettySection(String? section) {
    final s = (section ?? '').trim().toLowerCase();
    if (s.isEmpty) return tr('sec_na');
    if (s == 'sub-junior' || s == 'sub junior') return tr('sec_sub');
    if (s == 'junior') return tr('sec_jun');
    if (s == 'senior') return tr('sec_sen');
    return s[0].toUpperCase() + s.substring(1);
  }

  static String normalizeSection(String? section) {
    final s = (section ?? '').trim().toLowerCase();
    if (s == 'sub junior' || s == 'sub-junior' || s == 'subjunior') {
      return 'sub-junior';
    }
    return s;
  }

  static String idNumberOf(Map<String, dynamic> row) =>
      (row['student_id_number'] ?? '').toString().trim();

  /// Full student row for the card (fresh photo/ID/section every open).
  static Future<Map<String, dynamic>?> fetchStudent(String rowId) async {
    if (rowId.isEmpty) return null;
    try {
      final row = await _client
          .from('students')
          .select('*')
          .eq('id', rowId)
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  /// Returns the student's permanent ID, assigning one first when
  /// missing. With [forceNew], mints a brand-new number (Admin
  /// re-generate only). Retries on unique-conflicts so concurrent
  /// generates can never produce duplicates.
  static Future<String> ensureId(
    String rowId, {
    bool forceNew = false,
  }) async {
    if (rowId.isEmpty) return '';
    if (!forceNew) {
      try {
        final row = await _client
            .from('students')
            .select('student_id_number')
            .eq('id', rowId)
            .maybeSingle();
        final existing = (row?['student_id_number'] ?? '').toString().trim();
        if (existing.isNotEmpty) return existing;
      } catch (_) {}
    }
    for (var attempt = 0; attempt < 4; attempt++) {
      final candidate = await _nextNumber();
      if (candidate.isEmpty) return '';
      try {
        await _client
            .from('students')
            .update({'student_id_number': candidate})
            .eq('id', rowId);
        return candidate;
      } catch (_) {
        // Unique violation (someone took it first) → recompute + retry.
        await Future.delayed(const Duration(milliseconds: 120));
      }
    }
    return '';
  }

  /// Next free `C-NNNN`: max existing + 1 (floor: [firstNumber]).
  /// Malformed values are ignored, never crash the sequence.
  static Future<String> _nextNumber() async {
    try {
      final rows =
          await _client.from('students').select('student_id_number');
      var max = firstNumber - 1;
      for (final r in (rows as List)) {
        final raw = ((r as Map)['student_id_number'] ?? '').toString().trim();
        final m = RegExp(r'^C-(\d{1,8})$', caseSensitive: false)
            .firstMatch(raw);
        if (m == null) continue;
        final n = int.tryParse(m.group(1)!);
        if (n != null && n > max) max = n;
      }
      return 'C-${max + 1}';
    } catch (_) {
      return '';
    }
  }
}
