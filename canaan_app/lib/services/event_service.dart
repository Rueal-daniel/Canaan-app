import 'package:flutter/material.dart';

/// Shared Events & Calendar logic for Admin / Teacher / Student.
///
/// Backed by the `events` table (see `supabase/events.sql` — run once):
///   id, title, event_date (DATE), start_time, end_time, location,
///   event_type, description, audience, section, attachment_url,
///   attachment_name, status, created_by, created_by_id,
///   published_at, created_at, updated_at
///
/// Canonical values:
///   event_type : sunday_school | activity | special_program | others
///   audience   : everyone | students | teachers
///   section    : all | sub-junior | junior | senior
///                (multi-section stored comma-separated: 'junior,senior')
///   status     : published | draft  (only published is visible to
///                teachers/students; Admin sees everything)
///
/// Visibility (enforced at the query/UI layer — never fetch-all-then-hide
/// more than necessary; the table is small and date-ordered):
///   Admin   → everything (any status/audience/section).
///   Teacher → published events of any audience (teachers supervise
///             student events too), all sections.
///   Student → published events with audience everyone|students AND a
///             section match (all, or containing the student's section).
class EventService {
  static const table = 'events';

  // -- event types ---------------------------------------------------------
  static const typeSundaySchool = 'sunday_school';
  static const typeActivity = 'activity';
  static const typeSpecial = 'special_program';
  static const typeOthers = 'others';

  static const types = [
    typeSundaySchool,
    typeActivity,
    typeSpecial,
    typeOthers,
  ];

  static String normalizeType(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'sunday school' ||
        s == 'sunday_school' ||
        s == 'sundayschool') {
      return typeSundaySchool;
    }
    if (s == 'special program' ||
        s == 'special_program' ||
        s == 'special' ||
        s == 'monthly special' ||
        s == 'monthly special program') {
      return typeSpecial;
    }
    if (s == 'activity' || s == 'activities') return typeActivity;
    return typeOthers;
  }

  static String prettyType(String? raw) {
    switch (normalizeType(raw)) {
      case typeSundaySchool:
        return 'Sunday School';
      case typeActivity:
        return 'Activity';
      case typeSpecial:
        return 'Special Program';
      default:
        return 'Others';
    }
  }

  static IconData iconFor(String? raw) {
    switch (normalizeType(raw)) {
      case typeSundaySchool:
        return Icons.menu_book_rounded;
      case typeActivity:
        return Icons.celebration_rounded;
      case typeSpecial:
        return Icons.star_rounded;
      default:
        return Icons.event_rounded;
    }
  }

  // -- audience --------------------------------------------------------------
  static const audienceEveryone = 'everyone';
  static const audienceStudents = 'students';
  static const audienceTeachers = 'teachers';

  static String normalizeAudience(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'students' || s == 'student') return audienceStudents;
    if (s == 'teachers' || s == 'teacher') return audienceTeachers;
    return audienceEveryone;
  }

  static String prettyAudience(String? raw) {
    switch (normalizeAudience(raw)) {
      case audienceStudents:
        return 'Students';
      case audienceTeachers:
        return 'Teachers';
      default:
        return 'Everyone';
    }
  }

  // -- sections ---------------------------------------------------------------
  static const sectionAll = 'all';
  static const sectionSubJunior = 'sub-junior';
  static const sectionJunior = 'junior';
  static const sectionSenior = 'senior';

  static const sections = [
    sectionSubJunior,
    sectionJunior,
    sectionSenior,
  ];

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

  /// Sections stored on a row → normalized slug list.
  /// `'all'` (or empty/legacy 'All Sections') → [sectionAll] = everyone.
  /// `'junior,senior'` → [junior, senior].
  static List<String> sectionsOf(Map<String, dynamic> row) {
    final raw = (row['section'] ?? '').toString();
    final parts = raw
        .split(RegExp(r'[,;|/+]'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return [sectionAll];
    final out = <String>[];
    for (final p in parts) {
      final n = normalizeSection(p);
      if (n == sectionAll) return [sectionAll];
      if (!out.contains(n)) out.add(n);
    }
    return out.isEmpty ? [sectionAll] : out;
  }

  static bool sectionCoversAll(Map<String, dynamic> row) =>
      sectionsOf(row).contains(sectionAll);

  static String prettySections(Map<String, dynamic> row) {
    final secs = sectionsOf(row);
    if (secs.contains(sectionAll)) return 'All Sections';
    return secs.map(prettySection).join(' + ');
  }

  /// Canonical slug list for writes, e.g. ['junior','senior'] → 'junior,senior'.
  static String sectionSlugForWrite(List<String> normalized) {
    final clean = normalized
        .map(normalizeSection)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (clean.isEmpty || clean.contains(sectionAll)) return sectionAll;
    final ordered = sections.where(clean.contains).toList();
    return ordered.join(',');
  }

  // -- status ------------------------------------------------------------------
  static const statusPublished = 'published';
  static const statusDraft = 'draft';

  static String normalizeStatus(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'draft' || s == 'unpublished') return statusDraft;
    return statusPublished;
  }

  static bool isPublished(Map<String, dynamic> row) =>
      normalizeStatus(row['status']?.toString()) == statusPublished;

  // -- dates & times --------------------------------------------------------------
  static const fullMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  static const shortMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static const weekdaysShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  /// Parses `event_date` (DATE `yyyy-MM-dd`, possibly with time suffix).
  static DateTime? dateOf(Map<String, dynamic> row) {
    final raw = (row['event_date'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw.length >= 10 ? raw.substring(0, 10) : raw);
    } catch (_) {
      return null;
    }
  }

  /// `yyyy-MM-dd` key for grouping a [DateTime] by day.
  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String dateKeyOf(Map<String, dynamic> row) {
    final d = dateOf(row);
    return d == null ? '' : dateKey(d);
  }

  /// `September 19, 2026`.
  static String prettyDate(Map<String, dynamic> row) {
    final d = dateOf(row);
    if (d == null) return (row['event_date'] ?? '').toString().split('T').first;
    return '${fullMonths[d.month - 1]} ${d.day}, ${d.year}';
  }

  static String prettyDateOfDay(DateTime d) =>
      '${fullMonths[d.month - 1]} ${d.day}, ${d.year}';

  static String monthLabel(int year, int month) =>
      '${fullMonths[month - 1]} $year';

  static String timeRangeOf(Map<String, dynamic> row) {
    final s = (row['start_time'] ?? '').toString().trim();
    final e = (row['end_time'] ?? '').toString().trim();
    if (s.isEmpty && e.isEmpty) return '';
    if (s.isNotEmpty && e.isNotEmpty) return '$s – $e';
    return s.isNotEmpty ? s : e;
  }

  // -- visibility -------------------------------------------------------------------
  ///
  /// Admin   → everything.
  /// Teacher → published events of any audience (all sections).
  /// Student → published + audience everyone|students + section match.
  static bool visibleTo(
    Map<String, dynamic> row, {
    required String role,
    String? section,
  }) {
    final r = role.trim().toLowerCase();
    if (r == 'admin') return true;
    if (!isPublished(row)) return false;
    final audience = normalizeAudience(row['audience']?.toString());
    if (r == 'teacher') return true;
    if (r == 'student') {
      if (audience != audienceEveryone && audience != audienceStudents) {
        return false;
      }
      final secs = sectionsOf(row);
      if (secs.contains(sectionAll)) return true;
      final mine = normalizeSection(section);
      if (mine == sectionAll) return true;
      return secs.contains(mine);
    }
    return false;
  }

  // -- grouping / sorting --------------------------------------------------------------
  static Map<String, List<Map<String, dynamic>>> groupByDate(
      List<Map<String, dynamic>> events) {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final e in events) {
      final k = dateKeyOf(e);
      if (k.isEmpty) continue;
      out.putIfAbsent(k, () => []).add(e);
    }
    for (final list in out.values) {
      list.sort((a, b) {
        final sa = (a['start_time'] ?? '').toString();
        final sb = (b['start_time'] ?? '').toString();
        final c = sa.compareTo(sb);
        if (c != 0) return c;
        return (a['title'] ?? '').toString().compareTo(
              (b['title'] ?? '').toString(),
            );
      });
    }
    return out;
  }

  static List<Map<String, dynamic>> sortedByDate(
    List<Map<String, dynamic>> events, {
    bool ascending = true,
  }) {
    final list = List<Map<String, dynamic>>.from(events);
    list.sort((a, b) {
      final da = dateOf(a);
      final db = dateOf(b);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      final c = da.compareTo(db);
      if (c != 0) return ascending ? c : -c;
      final sa = (a['start_time'] ?? '').toString();
      final sb = (b['start_time'] ?? '').toString();
      return ascending ? sa.compareTo(sb) : sb.compareTo(sa);
    });
    return list;
  }

  static List<Map<String, dynamic>> upcoming(
    List<Map<String, dynamic>> events, {
    DateTime? from,
  }) {
    final start = from ?? DateTime.now();
    final dayStart = DateTime(start.year, start.month, start.day);
    return sortedByDate(events)
        .where((e) {
          final d = dateOf(e);
          return d != null && !d.isBefore(dayStart);
        })
        .toList();
  }

  // -- calendar helpers ------------------------------------------------------------------
  static int daysInMonth(int year, int month) {
    final next = month == 12
        ? DateTime(year + 1, 1, 1)
        : DateTime(year, month + 1, 1);
    return next.subtract(const Duration(days: 1)).day;
  }

  /// 0 = Sunday … 6 = Saturday (matches the Sun-first header).
  static int firstWeekday(int year, int month) =>
      DateTime(year, month, 1).weekday % 7;

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
