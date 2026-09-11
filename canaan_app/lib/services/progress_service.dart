import 'package:supabase_flutter/supabase_flutter.dart';

import 'language_service.dart';
import 'leave_service.dart';
import 'recitation_service.dart';

/// Central Student Progress calculations for the Canaan app.
///
/// SOURCE OF TRUTH (never duplicated):
///   Attendance %  ← `attendance_reports` (students JSON per date+section),
///                   same matching the My Attendance page uses.
///   Memory Verse %← per-section recitation tables
///                   (`recitation_sub_junior` / `_junior` / `_senior`)
///                   keyed by student_id.
///   Participation / Discipline / Stars ← `student_progress_evaluations`
///                   (the ONLY progress data stored; see
///                   `supabase/student_progress.sql`).
///
/// Every percentage shown anywhere (dashboard card, detail page, admin
/// list, evaluation screen) comes through here, so numbers always agree.
class ProgressService {
  static SupabaseClient get _client => Supabase.instance.client;

  static const evalTable = 'student_progress_evaluations';

  static const ratingExcellent = 'Excellent';
  static const ratingVeryGood = 'Very Good';
  static const ratingGood = 'Good';
  static const ratingNeedsImprovement = 'Needs Improvement';

  static const ratings = [
    ratingExcellent,
    ratingVeryGood,
    ratingGood,
    ratingNeedsImprovement,
  ];

  static String norm(String? v) => (v ?? '').trim().toLowerCase();

  static String normalizeSection(String? section) =>
      LeaveService.normalizeSection(section);

  // -- star labels --------------------------------------------------------------

  /// 1 Needs Improvement · 2 Developing · 3 Good · 4 Very Good ·
  /// 5 Excellent · 0/unrated Not Rated.
  static String starLabel(int stars) {
    switch (stars) {
      case 1:
        return tr('pg_star_need');
      case 2:
        return tr('pg_star_dev');
      case 3:
        return tr('pg_star_good');
      case 4:
        return tr('pg_star_vgood');
      case 5:
        return tr('pg_star_exc');
      default:
        return tr('pg_star_none');
    }
  }

  /// Dashboard card line under the stars: `Excellent Progress`.
  static String overallCardLabel(int stars) {
    if (stars <= 0) return tr('pg_not_rated');
    return trp('pg_overall_fmt', {'x': starLabel(stars)});
  }

  /// `92%` (whole numbers stay whole, fractions keep 1 decimal).
  static String pctLabel(double percent) {
    final v = percent.clamp(0, 100);
    return v % 1 == 0 ? '${v.toInt()}%' : '${v.toStringAsFixed(1)}%';
  }

  // -- attendance (from attendance_reports) ---------------------------------------

  /// All (date, status) sessions for [fullName], newest first.
  static Future<List<AttendancePoint>> attendanceRecords(
    String fullName,
  ) async {
    final me = norm(fullName);
    if (me.isEmpty) return [];
    try {
      final rows = await _client
          .from('attendance_reports')
          .select('date, students')
          .order('date', ascending: false);
      final out = <AttendancePoint>[];
      for (final row in (rows as List)) {
        final map = Map<String, dynamic>.from(row as Map);
        final students = map['students'];
        if (students is! List) continue;
        for (final s in students) {
          if (s is! Map) continue;
          if (norm(s['name']?.toString()) != me) continue;
          out.add(AttendancePoint(
            date: (map['date'] ?? '').toString(),
            status: norm(s['status']?.toString()),
          ));
          break; // one entry per report row
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static AttendanceSummary summarizeAttendance(
    List<AttendancePoint> records,
  ) {
    var present = 0;
    for (final r in records) {
      // Late counts as attended — same rule as the dashboards.
      if (r.status == 'present' || r.status == 'late') present++;
    }
    final total = records.length;
    return AttendanceSummary(
      total: total,
      present: present,
      absent: total - present,
      percent: total == 0 ? 0 : present * 100 / total,
    );
  }

  static Future<AttendanceSummary> attendanceFor(String fullName) async {
    return summarizeAttendance(await attendanceRecords(fullName));
  }

  // -- memory verse (from the section recitation table) ----------------------------

  /// All recitation rows for [studentId] in [section].
  static Future<List<MemoryPoint>> memoryRecords(
    String studentId,
    String section,
  ) async {
    final table =
        RecitationService.sectionTable(normalizeSection(section));
    if (table == null || studentId.isEmpty) return [];
    try {
      final rows = await _client
          .from(table)
          .select('status, date, verse_id')
          .eq('student_id', studentId)
          .order('date', ascending: false);
      return [
        for (final r in (rows as List))
          MemoryPoint(
            status: RecitationService.norm((r as Map)['status']),
            date: (r['date'] ?? '').toString(),
          ),
      ];
    } catch (_) {
      return [];
    }
  }

  /// Recited = 100% · Half Recited = 50% · Not Recited = 0%.
  static MemorySummary summarizeMemory(List<MemoryPoint> records) {
    var recited = 0;
    var half = 0;
    for (final r in records) {
      if (r.status == RecitationService.recited) {
        recited++;
      } else if (r.status == RecitationService.halfRecited) {
        half++;
      }
    }
    final total = records.length;
    return MemorySummary(
      total: total,
      recited: recited,
      halfRecited: half,
      notRecited: total - recited - half,
      percent: total == 0 ? 0 : (recited * 100 + half * 50) / total,
    );
  }

  static Future<MemorySummary> memoryFor(
    String studentId,
    String section,
  ) async {
    return summarizeMemory(await memoryRecords(studentId, section));
  }

  // -- admin evaluation (the only stored progress data) -----------------------------

  static Future<Map<String, dynamic>?> evaluationFor(String studentId) async {
    if (studentId.isEmpty) return null;
    try {
      final row = await _client
          .from(evalTable)
          .select('*')
          .eq('student_id', studentId)
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  static int evalInt(Map<String, dynamic>? eval, String key) {
    final v = eval?[key];
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? 0;
  }

  static String evalString(Map<String, dynamic>? eval, String key,
      [String fallback = '']) {
    final v = (eval?[key] ?? '').toString().trim();
    return v.isEmpty ? fallback : v;
  }

  /// Display label for a stored rating value (stored English values
  /// never change — only the displayed label translates).
  static String ratingLabel(String? rating) {
    switch ((rating ?? '').trim()) {
      case 'Excellent':
        return tr('rate_exc');
      case 'Very Good':
        return tr('rate_vgood');
      case 'Good':
        return tr('rate_good');
      case 'Needs Improvement':
        return tr('rate_need');
      default:
        return (rating ?? '').trim();
    }
  }

  /// Creates or updates the student's evaluation row (one row per
  /// student). Never touches attendance/memory data.
  static Future<void> saveEvaluation({
    required String studentId,
    required String section,
    required int participationPercent,
    required String participationRating,
    String participationComment = '',
    required int disciplinePercent,
    required String disciplineRating,
    String disciplineComment = '',
    required int stars,
    String evaluatedBy = '',
  }) async {
    final now = DateTime.now().toIso8601String();
    final payload = <String, dynamic>{
      'student_id': studentId,
      'section': normalizeSection(section),
      'participation_percentage': participationPercent.clamp(0, 100),
      'participation_rating': participationRating,
      'participation_comment': participationComment.trim(),
      'discipline_percentage': disciplinePercent.clamp(0, 100),
      'discipline_rating': disciplineRating,
      'discipline_comment': disciplineComment.trim(),
      'overall_star_rating': stars.clamp(0, 5),
      'evaluated_at': now,
      'updated_at': now,
    };
    if (evaluatedBy.trim().isNotEmpty) {
      payload['evaluated_by'] = evaluatedBy.trim();
    }
    try {
      await _client.from(evalTable).upsert(
            payload,
            onConflict: 'student_id',
          );
      return;
    } catch (_) {}
    // Fallback for backends without upsert support: update-or-insert.
    try {
      final existing = await _client
          .from(evalTable)
          .select('id')
          .eq('student_id', studentId)
          .limit(1);
      if ((existing as List).isNotEmpty) {
        await _client
            .from(evalTable)
            .update(payload)
            .eq('student_id', studentId);
      } else {
        await _client.from(evalTable).insert(payload);
      }
    } catch (_) {
      rethrow;
    }
  }

  // -- monthly history (trailing calendar months, from dated records) -----------------

  static const _shortMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  /// Last [n] calendar months as (`yyyy-MM` key, `Jun` label) pairs.
  static List<MonthKey> lastMonths(int n) {
    final now = DateTime.now();
    final out = <MonthKey>[];
    for (var i = n - 1; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final key =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
      out.add(MonthKey(key: key, label: _shortMonths[d.month - 1]));
    }
    return out;
  }

  /// Per-month attendance + memory percentages for the trailing
  /// [months] calendar months. A month with no records yields null
  /// (drawn as a gap, never as a fake zero).
  static Future<ProgressHistory> historyFor({
    required String fullName,
    required String studentId,
    required String section,
    int months = 4,
  }) async {
    final keys = lastMonths(months);
    final attendance = <String, double?>{for (final m in keys) m.key: null};
    final memory = <String, double?>{for (final m in keys) m.key: null};
    try {
      final records = await attendanceRecords(fullName);
      final byMonth = <String, List<AttendancePoint>>{};
      for (final r in records) {
        final key = r.date.length >= 7 ? r.date.substring(0, 7) : '';
        if (!attendance.containsKey(key)) continue;
        (byMonth[key] ??= []).add(r);
      }
      for (final e in byMonth.entries) {
        attendance[e.key] = summarizeAttendance(e.value).percent;
      }
    } catch (_) {}
    try {
      final records = await memoryRecords(studentId, section);
      final byMonth = <String, List<MemoryPoint>>{};
      for (final r in records) {
        final key = r.date.length >= 7 ? r.date.substring(0, 7) : '';
        if (!memory.containsKey(key)) continue;
        (byMonth[key] ??= []).add(r);
      }
      for (final e in byMonth.entries) {
        memory[e.key] = summarizeMemory(e.value).percent;
      }
    } catch (_) {}
    return ProgressHistory(
      months: keys,
      attendance: attendance,
      memory: memory,
    );
  }

  // -- admin section overview (batched: 4 queries, computed in memory) ------------------

  /// Every student in [section] with attendance + memory + evaluation
  /// attached. Used by Admin → Students → Student Progress.
  static Future<List<StudentProgressBundle>> forSection(
    String section,
  ) async {
    final sec = normalizeSection(section);
    try {
      final studentsRes = await _client
          .from('students')
          .select('id, full_name, section')
          .eq('section', sec)
          .order('full_name');
      final students = List<Map<String, dynamic>>.from(studentsRes);

      List<Map<String, dynamic>> reports = [];
      try {
        final res = await _client
            .from('attendance_reports')
            .select('date, students')
            .eq('section', sec)
            .order('date', ascending: false);
        reports = List<Map<String, dynamic>>.from(res);
      } catch (_) {}

      final table = RecitationService.sectionTable(sec);
      List<Map<String, dynamic>> recitations = [];
      if (table != null) {
        try {
          final res = await _client
              .from(table)
              .select('student_id, status, date');
          recitations = List<Map<String, dynamic>>.from(res);
        } catch (_) {}
      }

      List<Map<String, dynamic>> evals = [];
      try {
        final res = await _client
            .from(evalTable)
            .select('*')
            .eq('section', sec);
        evals = List<Map<String, dynamic>>.from(res);
      } catch (_) {}
      final evalByStudent = {
        for (final e in evals) (e['student_id'] ?? '').toString(): e,
      };

      // Attendance records grouped by normalized student name.
      final attByName = <String, List<AttendancePoint>>{};
      for (final rep in reports) {
        final date = (rep['date'] ?? '').toString();
        final list = rep['students'];
        if (list is! List) continue;
        for (final s in list) {
          if (s is! Map) continue;
          final name = norm(s['name']?.toString());
          if (name.isEmpty) continue;
          (attByName[name] ??= []).add(AttendancePoint(
            date: date,
            status: norm(s['status']?.toString()),
          ));
        }
      }

      final memByStudent = <String, List<MemoryPoint>>{};
      for (final r in recitations) {
        final sid = (r['student_id'] ?? '').toString();
        if (sid.isEmpty) continue;
        (memByStudent[sid] ??= []).add(MemoryPoint(
          status: RecitationService.norm(r['status']?.toString()),
          date: (r['date'] ?? '').toString(),
        ));
      }

      return [
        for (final s in students)
          StudentProgressBundle(
            studentId: (s['id'] ?? '').toString(),
            fullName: (s['full_name'] ?? '').toString(),
            section: (s['section'] ?? sec).toString(),
            attendance: summarizeAttendance(
                attByName[norm(s['full_name']?.toString())] ?? []),
            memory: summarizeMemory(
                memByStudent[(s['id'] ?? '').toString()] ?? []),
            evaluation:
                evalByStudent[(s['id'] ?? '').toString()],
          ),
      ];
    } catch (_) {
      return [];
    }
  }
}

/// One attendance session: ISO date + present|absent|late.
class AttendancePoint {
  final String date;
  final String status;
  const AttendancePoint({required this.date, required this.status});
}

/// One recitation row: recited|half_recited|not_recited + ISO date.
class MemoryPoint {
  final String status;
  final String date;
  const MemoryPoint({required this.status, required this.date});
}

class AttendanceSummary {
  final int total;
  final int present;
  final int absent;
  final double percent;
  const AttendanceSummary({
    required this.total,
    required this.present,
    required this.absent,
    required this.percent,
  });
}

class MemorySummary {
  final int total;
  final int recited;
  final int halfRecited;
  final int notRecited;
  final double percent;
  const MemorySummary({
    required this.total,
    required this.recited,
    required this.halfRecited,
    required this.notRecited,
    required this.percent,
  });
}

class MonthKey {
  final String key;
  final String label;
  const MonthKey({required this.key, required this.label});
}

class ProgressHistory {
  final List<MonthKey> months;
  final Map<String, double?> attendance;
  final Map<String, double?> memory;
  const ProgressHistory({
    required this.months,
    required this.attendance,
    required this.memory,
  });
}

/// One student with everything the admin cards need.
class StudentProgressBundle {
  final String studentId;
  final String fullName;
  final String section;
  final AttendanceSummary attendance;
  final MemorySummary memory;
  final Map<String, dynamic>? evaluation;
  const StudentProgressBundle({
    required this.studentId,
    required this.fullName,
    required this.section,
    required this.attendance,
    required this.memory,
    this.evaluation,
  });

  int get stars {
    final v = evaluation?['overall_star_rating'];
    if (v is num) return v.toInt().clamp(0, 5);
    return (int.tryParse((v ?? '').toString()) ?? 0).clamp(0, 5);
  }

  int get participation =>
      ProgressService.evalInt(evaluation, 'participation_percentage');
  int get discipline =>
      ProgressService.evalInt(evaluation, 'discipline_percentage');
}
