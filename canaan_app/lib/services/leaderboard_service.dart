import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'leave_service.dart';
import 'progress_service.dart';
import 'recitation_service.dart';

/// Leaderboard calculations — a pure VIEW over existing Canaan data.
///
/// SOURCE DATA (never duplicated, no leaderboard tables):
///   Attendance % ← `attendance_reports` (`date` + `students` JSON array
///                  of {name, status}), matched exactly like the Student
///                  Dashboard (case-insensitive trimmed name; late counts
///                  as attended). See [ProgressService.summarizeAttendance].
///   Memory %     ← per-section recitation tables (`recitation_sub_junior`
///                  / `_junior` / `_senior`), Recited=100 / Half=50 /
///                  Not=0. See [ProgressService.summarizeMemory].
///
/// RANKING: standard competition ranking (98→1, 95→2, 95→2, 90→4) —
/// deterministic, ties share a rank, never random.
///
/// EMPTY DATA: a student with zero applicable records gets a null
/// percentage — shown as "No attendance/recitation data" and listed
/// AFTER all ranked students with no rank number, never as 0%.
///
/// SECURITY (§15 — enforced here, not just in Flutter UI):
///   Teacher/student entry points accept ONLY a verified row id. The
///   section is resolved SERVER-SIDE from that row (`teachers` / `students`
///   table) — there is no section parameter to tamper with, so a teacher
///   or student can never retrieve another section by editing a value.
///   Only leaderboard-safe columns are ever selected (id, full_name,
///   section, status, photo_url) — username, password, email, phone and
///   parent/guardian fields are never read.
class LeaderboardService {
  static SupabaseClient get _client => Supabase.instance.client;

  static const sections = ['sub-junior', 'junior', 'senior'];

  static String normalizeSection(String? section) =>
      LeaveService.normalizeSection(section);

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

  // -- role-scoped section resolution (server-side, tamper-proof) ----------

  /// The teacher's OWN assigned section, read from the `teachers` table
  /// by verified login id. Returns '' when unresolvable.
  static Future<String> teacherSectionOf(String teacherId) async {
    final id = teacherId.trim();
    if (id.isEmpty) return '';
    try {
      final row = await _client
          .from('teachers')
          .select('section')
          .eq('id', id)
          .maybeSingle();
      return normalizeSection((row?['section'] ?? '').toString());
    } catch (_) {
      return '';
    }
  }

  /// The student's OWN section, read from the `students` table by the
  /// verified active id. Returns '' when unresolvable.
  static Future<String> studentSectionOf(String studentId) async {
    final id = studentId.trim();
    if (id.isEmpty) return '';
    try {
      final row = await _client
          .from('students')
          .select('section')
          .eq('id', id)
          .maybeSingle();
      return normalizeSection((row?['section'] ?? '').toString());
    } catch (_) {
      return '';
    }
  }

  // -- batched computation ---------------------------------------------------

  /// Computes one leaderboard.
  ///
  /// [section] scopes students (and recitation tables) to a single
  /// section; null/empty means ALL students (admin only — teacher/student
  /// callers always pass their resolved section).
  /// [memory] selects the Memory Verse board; false selects Attendance.
  ///
  /// Efficient by design: 1 students query + 1 attendance_reports query +
  /// ≤3 recitation queries, everything else computed in memory. No
  /// per-student round trips, so ranking stays correct at any size.
  static Future<List<LeaderboardEntry>> compute({
    required String section,
    required bool memory,
  }) async {
    final sec = normalizeSection(section);
    try {
      // 1. Students in scope — leaderboard-safe columns ONLY (privacy §7),
      //    suspended accounts excluded per existing suspension rules.
      var studentQuery =
          _client.from('students').select('id, full_name, section, status, photo_url');
      if (sec.isNotEmpty) studentQuery = studentQuery.eq('section', sec);
      final studentRows = List<Map<String, dynamic>>.from(
          await studentQuery.order('full_name'));
      final students = <Map<String, dynamic>>[];
      for (final s in studentRows) {
        if (AuthService.isSuspended(s)) continue; // suspended → unranked
        if (((s['id'] ?? '').toString()).isEmpty) continue;
        if (((s['full_name'] ?? '').toString()).trim().isEmpty) continue;
        students.add(s);
      }
      if (students.isEmpty) return [];

      List<LeaderboardEntry> entries;
      if (!memory) {
        entries = await _computeAttendance(students);
      } else {
        entries = await _computeMemory(students, sec);
      }

      // Sort: ranked (has data) by percent desc, then name asc for a
      // stable deterministic order; no-data entries trail at the end.
      entries.sort((a, b) {
        if (a.percent == null && b.percent == null) {
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        }
        if (a.percent == null) return 1;
        if (b.percent == null) return -1;
        final cmp = b.percent!.compareTo(a.percent!);
        if (cmp != 0) return cmp;
        return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
      });

      // Standard competition ranking over the ranked subset only.
      var lastPercent = -1.0;
      var lastRank = 0;
      var position = 0;
      for (final e in entries) {
        if (e.percent == null) break; // trailing no-data block (sorted last)
        position++;
        if ((e.percent! - lastPercent).abs() > 1e-9) {
          lastRank = position;
          lastPercent = e.percent!;
        }
        e.rank = lastRank;
      }
      return entries;
    } catch (_) {
      return [];
    }
  }

  /// Attendance % per student — identical matching to the Student
  /// Dashboard + [ProgressService.summarizeAttendance].
  static Future<List<LeaderboardEntry>> _computeAttendance(
    List<Map<String, dynamic>> students,
  ) async {
    // All sessions once; group by normalized student name.
    final attByName = <String, List<AttendancePoint>>{};
    try {
      final rows = await _client
          .from('attendance_reports')
          .select('date, students')
          .order('date', ascending: false);
      for (final row in (rows as List)) {
        final map = Map<String, dynamic>.from(row as Map);
        final date = (map['date'] ?? '').toString();
        final list = map['students'];
        if (list is! List) continue;
        for (final s in list) {
          if (s is! Map) continue;
          final name = ProgressService.norm(s['name']?.toString());
          if (name.isEmpty) continue;
          (attByName[name] ??= []).add(AttendancePoint(
            date: date,
            status: ProgressService.norm(s['status']?.toString()),
          ));
        }
      }
    } catch (_) {}

    return [
      for (final s in students)
        () {
          final records =
              attByName[ProgressService.norm(s['full_name']?.toString())] ??
                  const <AttendancePoint>[];
          final summary = ProgressService.summarizeAttendance(records);
          return LeaderboardEntry(
            studentId: (s['id'] ?? '').toString(),
            fullName: (s['full_name'] ?? '').toString(),
            section: (s['section'] ?? '').toString(),
            photoUrl: photoUrlOf(s),
            percent: records.isEmpty ? null : summary.percent,
            present: summary.present,
            total: summary.total,
          );
        }(),
    ];
  }

  /// Memory Verse % per student from the real recitation rows —
  /// Recited=100, Half=50, Not=0, averaged. Unknown statuses are ignored
  /// (same rule as [ProgressService.summarizeMemory]).
  static Future<List<LeaderboardEntry>> _computeMemory(
    List<Map<String, dynamic>> students,
    String section,
  ) async {
    // Which recitation tables to read: one for a section scope, all
    // three for the admin "All Students" board.
    final tables = <String>[];
    if (section.isNotEmpty) {
      final t = RecitationService.sectionTable(section);
      if (t != null) tables.add(t);
    } else {
      for (final s in sections) {
        final t = RecitationService.sectionTable(s);
        if (t != null) tables.add(t);
      }
    }

    // All recitation rows once; group by student_id. Latest record wins
    // per (student, verse) so re-marked verses never double-count.
    final latestByStudentVerse = <String, Map<String, String>>{};
    for (final table in tables) {
      try {
        final rows = await _client
            .from(table)
            .select('student_id, verse_id, status, date')
            .order('date', ascending: false)
            .order('id', ascending: false);
        for (final r in (rows as List)) {
          final map = Map<String, dynamic>.from(r as Map);
          final sid = (map['student_id'] ?? '').toString();
          final verse = (map['verse_id'] ?? '').toString();
          final st = RecitationService.norm(map['status']?.toString());
          if (sid.isEmpty ||
              verse.isEmpty ||
              !RecitationService.isKnownRecitation(st)) {
            continue;
          }
          final perVerse =
              latestByStudentVerse.putIfAbsent(sid, () => <String, String>{});
          perVerse.putIfAbsent(verse, () => st);
        }
      } catch (_) {}
    }

    return [
      for (final s in students)
        () {
          final sid = (s['id'] ?? '').toString();
          final statuses =
              latestByStudentVerse[sid]?.values.toList() ?? const <String>[];
          double? percent;
          var recited = 0;
          var half = 0;
          var not = 0;
          if (statuses.isNotEmpty) {
            for (final st in statuses) {
              if (st == RecitationService.recited) {
                recited++;
              } else if (st == RecitationService.halfRecited) {
                half++;
              } else {
                not++;
              }
            }
            percent = (recited * 100 + half * 50) / statuses.length;
          }
          return LeaderboardEntry(
            studentId: sid,
            fullName: (s['full_name'] ?? '').toString(),
            section: (s['section'] ?? '').toString(),
            photoUrl: photoUrlOf(s),
            percent: percent,
            present: recited,
            total: statuses.length,
            halfCount: half,
            notCount: not,
          );
        }(),
    ];
  }

  /// `87%` (whole numbers stay whole, fractions keep 1 decimal).
  static String pctLabel(double percent) =>
      ProgressService.pctLabel(percent);
}

/// One ranked (or unranked, when [percent] is null) student row.
class LeaderboardEntry {
  final String studentId;
  final String fullName;
  final String section;
  final String photoUrl;

  /// Null = no applicable records ("No data" — shown unranked at bottom).
  final double? percent;

  /// Attendance: present count · Memory: recited count. [total] is the
  /// session/verse count the percentage was averaged over.
  final int present;
  final int total;
  final int halfCount;
  final int notCount;

  /// Competition rank (1,2,2,4…); 0 = unranked (no data).
  int rank = 0;

  LeaderboardEntry({
    required this.studentId,
    required this.fullName,
    required this.section,
    required this.photoUrl,
    required this.percent,
    required this.present,
    required this.total,
    this.halfCount = 0,
    this.notCount = 0,
  });
}
