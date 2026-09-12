import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared Student Update logic (Admin writes, Student reads own only).
///
/// Backed by `student_updates` (see `supabase/student_updates.sql`):
///   id, student_id, student_name, section, behaviour_detail,
///   saturday_rating (1–5), total_percentage (0–100), additional_notes,
///   created_by, created_by_id, created_at, updated_at
///
/// The three admin textareas (did today / learned / behaviour) are
/// combined into the single `behaviour_detail` column with fixed
/// section headers, and split apart again for display — the student
/// sees "What I Did Today → What I Learned → My Behaviour" while the
/// database keeps one column.
///
/// Rating + percentage belong ONLY to the update and never feed the
/// existing Attendance / Progress calculations.
class StudentUpdateService {
  static const table = 'student_updates';

  // -- behaviour_detail packing ---------------------------------------------------
  static const didHeader = 'What Did the Student Do Today?';
  static const learnedHeader = 'What Did the Student Learn?';
  static const behaviourHeader = 'Behaviour';

  /// Packs the three admin textareas into one storable column.
  static String combineDetail({
    required String didToday,
    required String learned,
    required String behaviour,
  }) {
    return '$didHeader\n${didToday.trim()}\n\n'
        '$learnedHeader\n${learned.trim()}\n\n'
        '$behaviourHeader\n${behaviour.trim()}';
  }

  /// Splits a stored column back into (didToday, learned, behaviour).
  /// Falls back to showing the whole text as behaviour when the
  /// headers are absent (e.g. legacy hand-written rows).
  static (String, String, String) splitDetail(String? raw) {
    final src = (raw ?? '').trim();
    if (src.isEmpty) return ('', '', '');
    String section(String header, String? nextHeader) {
      final start = src.indexOf(header);
      if (start < 0) return '';
      var body = src.substring(start + header.length);
      if (nextHeader != null) {
        final end = body.indexOf(nextHeader);
        if (end >= 0) body = body.substring(0, end);
      }
      return body.trim();
    }

    final did = section(didHeader, learnedHeader);
    final learned = section(learnedHeader, behaviourHeader);
    final behaviour = section(behaviourHeader, null);
    if (did.isEmpty && learned.isEmpty && behaviour.isEmpty) {
      return ('', '', src);
    }
    return (did, learned, behaviour);
  }

  // -- validation ----------------------------------------------------------------------
  static int clampRating(int v) => v.clamp(1, 5);

  static int clampPercentage(int v) => v.clamp(0, 100);

  /// Returns an error string, or null when [raw] is a valid 0–100 int.
  static String? validatePercentage(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return 'Please enter a percentage';
    final v = int.tryParse(s);
    if (v == null) return 'Enter a whole number from 0 to 100';
    if (v < 0 || v > 100) return 'Percentage must be between 0 and 100';
    return null;
  }

  // -- display ------------------------------------------------------------------------------
  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  static const _fullMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  static DateTime? createdAtOf(Map<String, dynamic> row) {
    final raw = (row['created_at'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  /// `Saturday, September 12, 2026`.
  static String prettyDate(Map<String, dynamic> row) {
    final d = createdAtOf(row);
    if (d == null) {
      return (row['created_at'] ?? '').toString().split('T').first;
    }
    return '${_weekdays[d.weekday - 1]}, ${_fullMonths[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// `September 12, 2026` (short card subtitle).
  static String prettyShortDate(Map<String, dynamic> row) {
    final d = createdAtOf(row);
    if (d == null) {
      return (row['created_at'] ?? '').toString().split('T').first;
    }
    return '${_fullMonths[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// `yyyy-MM` key for the admin month filter.
  static String monthKeyOf(Map<String, dynamic> row) {
    final d = createdAtOf(row);
    if (d == null) return '';
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}';
  }

  static String monthLabel(int year, int month) =>
      '${_fullMonths[month - 1]} $year';

  /// `⭐⭐⭐⭐☆ (4/5)`.
  static String starsLabel(int rating) {
    final r = rating.clamp(0, 5);
    return '${'⭐' * r}${'☆' * (5 - r)} ($r/5)';
  }

  static int ratingOf(Map<String, dynamic> row) =>
      ((row['saturday_rating'] as num?)?.toInt() ?? 0).clamp(0, 5);

  static int percentageOf(Map<String, dynamic> row) =>
      ((row['total_percentage'] as num?)?.toInt() ?? 0).clamp(0, 100);

  static int updateIdOf(Map<String, dynamic> row) =>
      (row['id'] as num?)?.toInt() ?? -1;

  // -- sections -----------------------------------------------------------------------
  static const sectionAll = 'all';
  static const sectionSubJunior = 'sub-junior';
  static const sectionJunior = 'junior';
  static const sectionSenior = 'senior';

  static String normalizeSection(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'sub junior' ||
        s == 'sub-junior' ||
        s == 'subjunior' ||
        s == 'sub_junior') {
      return sectionSubJunior;
    }
    if (s == 'junior') return sectionJunior;
    if (s == 'senior') return sectionSenior;
    return sectionAll;
  }

  static String prettySection(String? raw) {
    switch (normalizeSection(raw)) {
      case sectionSubJunior:
        return 'Sub Junior';
      case sectionJunior:
        return 'Junior';
      case sectionSenior:
        return 'Senior';
      default:
        return 'All Sections';
    }
  }

  // -- teacher lookup (display only, never stored) -------------------------------
  /// Names of the teachers assigned to [section] (`students` rows point
  /// at sections, and so do `teachers` rows).
  static Future<String> teacherNamesFor(
      SupabaseClient client, String? section) async {
    final sec = normalizeSection(section);
    if (sec == sectionAll) return '';
    try {
      final rows =
          await client.from('teachers').select('full_name').eq('section', sec);
      final names = [
        for (final r in (rows as List))
          ((r as Map)['full_name'] ?? '').toString().trim(),
      ].where((n) => n.isNotEmpty).toList();
      return names.join(', ');
    } catch (_) {
      return '';
    }
  }
}
