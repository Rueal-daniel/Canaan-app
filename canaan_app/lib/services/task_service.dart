import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'language_service.dart';
import 'leave_service.dart';
import 'lesson_plan_service.dart';
import 'notification_service.dart';

/// Central Teacher Task Management logic.
///
/// SOURCE OF TRUTH (never duplicated):
///   teacher_tasks             → ONE row per Admin-created task.
///   teacher_task_assignments  → one row per (task, teacher) holding ONLY
///                               that teacher's status + completed_at.
///
/// Statuses: not_completed (default) · working · completed.
/// Overdue / Due Soon / Due Today are DERIVED from the due date, never
/// stored — an overdue task is never auto-completed.
class TaskService {
  static SupabaseClient get _client => Supabase.instance.client;

  static const tasksTable = 'teacher_tasks';
  static const assignTable = 'teacher_task_assignments';
  static const warningsTable = 'teacher_task_warnings';

  static const statusNotCompleted = 'not_completed';
  static const statusWorking = 'working';
  static const statusCompleted = 'completed';

  static const statuses = [
    statusNotCompleted,
    statusWorking,
    statusCompleted,
  ];

  /// Predefined task types (Admin may also type a custom one).
  static const predefinedTypes = [
    'Memory Verse',
    'Memory Verse Recitation Report',
    'Attendance Report',
    'Lesson Preparation',
    'Student Progress',
    'Student Activity',
    'Class Preparation',
    'Report Submission',
    'Parent Communication',
    'Other',
  ];

  static String norm(String? v) => (v ?? '').trim().toLowerCase();

  static String normalizeSection(String? section) =>
      LeaveService.normalizeSection(section);

  static String prettySection(String? section) {
    final s = normalizeSection(section);
    if (s.isEmpty || s == 'all') return 'All Sections';
    if (s == 'sub-junior') return 'Sub Junior';
    return s[0].toUpperCase() + s.substring(1);
  }

  // -- status presentation -------------------------------------------------------

  static String statusLabel(String? status) {
    switch (norm(status)) {
      case statusWorking:
        return tr('st_working');
      case statusCompleted:
        return tr('st_completed');
      default:
        return tr('st_nc');
    }
  }

  static Color statusColor(String? status, {bool overdue = false}) {
    if (overdue && norm(status) != statusCompleted) {
      return const Color(0xFFEF4444);
    }
    switch (norm(status)) {
      case statusWorking:
        return const Color(0xFFF59E0B);
      case statusCompleted:
        return const Color(0xFF22C55E);
      default:
        return const Color(0xFFEF4444);
    }
  }

  static IconData statusIcon(String? status, {bool overdue = false}) {
    if (overdue && norm(status) != statusCompleted) {
      return Icons.warning_amber_rounded;
    }
    switch (norm(status)) {
      case statusWorking:
        return Icons.hourglass_top_rounded;
      case statusCompleted:
        return Icons.check_circle_rounded;
      default:
        return Icons.radio_button_unchecked_rounded;
    }
  }

  static IconData typeIcon(String? type) {
    final t = norm(type);
    if (t.contains('memory')) return Icons.menu_book_rounded;
    if (t.contains('attendance')) return Icons.fact_check_rounded;
    if (t.contains('lesson') || t.contains('preparation')) {
      return Icons.auto_stories_rounded;
    }
    if (t.contains('progress')) return Icons.insights_rounded;
    if (t.contains('activity')) return Icons.celebration_rounded;
    if (t.contains('report') || t.contains('submission')) {
      return Icons.assignment_rounded;
    }
    if (t.contains('parent') || t.contains('communication')) {
      return Icons.family_restroom_rounded;
    }
    return Icons.task_alt_rounded;
  }

  // -- dates -----------------------------------------------------------------------

  /// `2026-09-19` for storage.
  static String dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? parseDate(String? raw) {
    final src = (raw ?? '').trim();
    if (src.isEmpty) return null;
    try {
      final d = DateTime.parse(src.length >= 10 ? src.substring(0, 10) : src);
      return DateTime(d.year, d.month, d.day);
    } catch (_) {
      return null;
    }
  }

  static const _fullMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  /// `September 19, 2026`.
  static String prettyDate(String? raw) {
    final d = parseDate(raw);
    if (d == null) return '—';
    return '${_fullMonths[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// Whole days from today to the due date (negative = overdue).
  static int? daysUntil(String? raw) {
    final d = parseDate(raw);
    if (d == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return d.difference(today).inDays;
  }

  static bool isOverdue(String status, String? dueRaw) {
    if (norm(status) == statusCompleted) return false;
    final days = daysUntil(dueRaw);
    return days != null && days < 0;
  }

  static bool isDueSoon(String status, String? dueRaw) {
    if (norm(status) == statusCompleted) return false;
    final days = daysUntil(dueRaw);
    return days != null && days >= 1 && days <= 3;
  }

  /// `Due Today` · `Due in 2 days` · `2 Days Overdue` · `No due date`.
  static String dueLabel(String? raw) {
    final days = daysUntil(raw);
    if (days == null) return tr('due_none');
    if (days < 0) {
      final n = -days;
      if (n == 1) return tr('due_over_1');
      return trp('due_over', {'n': '$n'});
    }
    if (days == 0) return tr('due_today');
    if (days == 1) return tr('due_tomorrow');
    return trp('due_in', {'n': '$days'});
  }

  /// Default due date for the form: the upcoming Saturday.
  static DateTime defaultDueDate() =>
      LessonPlanService.upcomingSaturday();

  // -- reads --------------------------------------------------------------------------

  /// Assignment + embedded task for [assignmentRow].
  static TaskAssignment assignmentFromParts(
    Map<String, dynamic> assignment,
    Map<String, dynamic>? task,
  ) {
    return TaskAssignment(
      id: (assignment['id'] ?? '').toString(),
      taskId: (assignment['task_id'] ?? task?['id'] ?? '').toString(),
      teacherId: (assignment['teacher_id'] ?? '').toString(),
      teacherName: (assignment['teacher_name'] ?? '').toString(),
      status: norm(assignment['status']),
      completedAt: (assignment['completed_at'] ?? '').toString(),
      createdAt: (assignment['created_at'] ?? '').toString(),
      title: ((task?['title'] ?? '')).toString(),
      description: ((task?['description'] ?? '')).toString(),
      taskType: ((task?['task_type'] ?? 'Other')).toString(),
      section: ((task?['section'] ?? '')).toString(),
      dueDate: ((task?['due_date'] ?? '')).toString(),
      createdBy: ((task?['created_by'] ?? '')).toString(),
    );
  }

  static Future<List<TaskAssignment>> _fetchAssignments({
    String? teacherId,
  }) async {
    try {
      // Single round trip via the FK; two-step fallback below.
      try {
        var query = _client.from(assignTable).select(
              'id,task_id,teacher_id,teacher_name,status,completed_at,'
              'created_at,updated_at,teacher_tasks(id,title,description,'
              'task_type,section,due_date,created_by,created_at,updated_at)',
            );
        if (teacherId != null && teacherId.isNotEmpty) {
          query = query.eq('teacher_id', teacherId);
        }
        final rows = await query.order('created_at', ascending: false);
        final out = <TaskAssignment>[];
        for (final r in (rows as List)) {
          final map = Map<String, dynamic>.from(r as Map);
          final rawTask = map['teacher_tasks'];
          Map<String, dynamic>? task;
          if (rawTask is Map) {
            task = Map<String, dynamic>.from(rawTask);
          } else if (rawTask is List && rawTask.isNotEmpty) {
            task = Map<String, dynamic>.from(rawTask.first as Map);
          }
          if (task == null) continue;
          out.add(assignmentFromParts(map, task));
        }
        return out;
      } catch (_) {
        return await _fetchAssignmentsTwoStep(teacherId: teacherId);
      }
    } catch (_) {
      return [];
    }
  }

  static Future<List<TaskAssignment>> _fetchAssignmentsTwoStep({
    String? teacherId,
  }) async {
    try {
      var query = _client.from(assignTable).select('*');
      if (teacherId != null && teacherId.isNotEmpty) {
        query = query.eq('teacher_id', teacherId);
      }
      final recips =
          await query.order('created_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(recips);
      if (list.isEmpty) return [];
      final ids = list
          .map((r) => (r['task_id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      final byId = <String, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        final tasks =
            await _client.from(tasksTable).select('*').inFilter('id', ids);
        for (final t in (tasks as List)) {
          final m = Map<String, dynamic>.from(t as Map);
          byId[(m['id'] ?? '').toString()] = m;
        }
      }
      final out = <TaskAssignment>[];
      for (final r in list) {
        final task = byId[(r['task_id'] ?? '').toString()];
        if (task == null) continue;
        out.add(assignmentFromParts(r, task));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Every assignment in the system (Admin monitoring).
  static Future<List<TaskAssignment>> fetchAll() =>
      _fetchAssignments();

  /// Assignments for one teacher only (Teacher Tasks).
  static Future<List<TaskAssignment>> fetchMine(String teacherId) =>
      _fetchAssignments(teacherId: teacherId);

  /// Teachers for the assignment picker (optionally section-filtered).
  static Future<List<Map<String, dynamic>>> teachersIn(
    String? section,
  ) async {
    try {
      var query =
          _client.from('teachers').select('id, full_name, section');
      final sec = normalizeSection(section);
      if (sec.isNotEmpty) query = query.eq('section', sec);
      final rows = await query.order('full_name');
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }

  // -- writes (Admin) ---------------------------------------------------------------------

  /// Creates the task ONCE + one assignment per teacher + notifies them.
  /// Returns the new task id, or '' on failure (callers show a snackbar;
  /// nothing is ever half-reported as success).
  static Future<String> createTask({
    required String title,
    required String description,
    required String taskType,
    required String section,
    required DateTime dueDate,
    required List<Map<String, dynamic>> teachers,
    required String createdBy,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final created = await _client
          .from(tasksTable)
          .insert({
            'title': title.trim(),
            'description': description.trim(),
            'task_type': taskType.trim().isEmpty ? 'Other' : taskType.trim(),
            'section': normalizeSection(section),
            'due_date': dateStr(dueDate),
            'created_by': createdBy.trim(),
            'created_at': now,
            'updated_at': now,
          })
          .select('id')
          .single();
      final taskId = (created['id'] ?? '').toString();
      if (taskId.isEmpty) return '';
      final seen = <String>{};
      final rows = <Map<String, dynamic>>[];
      for (final t in teachers) {
        final tid = (t['id'] ?? '').toString();
        if (tid.isEmpty || !seen.add(tid)) continue;
        rows.add({
          'task_id': int.tryParse(taskId) ?? taskId,
          'teacher_id': tid,
          'teacher_name': (t['full_name'] ?? '').toString(),
          'status': statusNotCompleted,
          'created_at': now,
          'updated_at': now,
        });
      }
      if (rows.isNotEmpty) {
        try {
          await _client.from(assignTable).insert(rows);
        } catch (_) {
          // Assignment rows are unique per (task, teacher): partial
          // failures still leave a usable task; admin can re-check.
        }
      }
      // 🔔 One event for the task + one recipient row per assigned
      // teacher (fire-and-forget; never blocks task creation).
      try {
        final teacherIds = rows
            .map((r) => (r['teacher_id'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toSet();
        if (teacherIds.isNotEmpty) {
          final eventId = await NotificationService.publishEvent(
            type: NotificationService.typeTeacherTask,
            title: 'New Teacher Task',
            message:
                'Admin has assigned you a new task: ${title.trim()}.',
            titleNe: 'नयाँ शिक्षक कार्य',
            messageNe:
                'प्रशासकले तपाईंलाई नयाँ कार्य तोक्नुभएको छ: ${title.trim()}।',
            relatedId: 'teacher_task:$taskId',
            destination: NotificationService.destTeacherTasks,
            audienceType: NotificationService.audienceIndividual,
          );
          if (eventId != null && eventId.isNotEmpty) {
            for (final tid in teacherIds) {
              await NotificationService.fanOut(
                notificationId: eventId,
                audience: NotificationService.audienceIndividual,
                userId: tid,
              );
            }
          }
        }
      } catch (_) {}
      return taskId;
    } catch (_) {
      return '';
    }
  }

  /// Edits the task itself (title/description/type/section/due date).
  /// Assignments + statuses are untouched.
  static Future<bool> updateTask({
    required String taskId,
    required String title,
    required String description,
    required String taskType,
    required String section,
    required DateTime dueDate,
  }) async {
    try {
      await _client.from(tasksTable).update({
        'title': title.trim(),
        'description': description.trim(),
        'task_type': taskType.trim().isEmpty ? 'Other' : taskType.trim(),
        'section': normalizeSection(section),
        'due_date': dateStr(dueDate),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', taskId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Deletes the task + all its assignments (FK cascade).
  static Future<bool> deleteTask(String taskId) async {
    try {
      await _client.from(tasksTable).delete().eq('id', taskId);
      return true;
    } catch (_) {
      return false;
    }
  }

  // -- warnings (Admin → teacher on overdue assignments) ----------------------------------------

  /// Sends an overdue warning to the teacher and notifies them.
  /// History is kept (newest first on both sides).
  static Future<bool> sendWarning({
    required String assignmentId,
    required String taskId,
    required String teacherId,
    required String teacherName,
    required String taskTitle,
    required String message,
    required String createdBy,
  }) async {
    final text = message.trim();
    if (assignmentId.isEmpty || teacherId.isEmpty || text.isEmpty) {
      return false;
    }
    try {
      final created = await _client
          .from(warningsTable)
          .insert({
            'assignment_id': assignmentId,
            'task_id': int.tryParse(taskId) ?? taskId,
            'teacher_id': teacherId,
            'teacher_name': teacherName.trim(),
            'message': text,
            'created_by': createdBy.trim(),
          })
          .select('id')
          .single();
      final warningId = (created['id'] ?? '').toString();
      // 🔔 Teacher receives the warning immediately.
      try {
        final short =
            text.length > 140 ? '${text.substring(0, 140)}…' : text;
        await NotificationService.publish(
          type: NotificationService.typeTeacherTask,
          title: '⚠️ Task Overdue Warning',
          message: '"${taskTitle.trim()}" is overdue. $short',
          titleNe: '⚠️ कार्य म्याद चेतावनी',
          messageNe:
              '"${taskTitle.trim()}" को म्याद नाघेको छ। $short',
          relatedId: 'teacher_task:$taskId:warning:$warningId',
          destination: NotificationService.destTeacherTasks,
          audience: NotificationService.audienceIndividual,
          userId: teacherId,
        );
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Warnings on one assignment, newest first.
  static Future<List<Map<String, dynamic>>> warningsForAssignment(
    String assignmentId,
  ) async {
    if (assignmentId.isEmpty) return [];
    try {
      final rows = await _client
          .from(warningsTable)
          .select('*')
          .eq('assignment_id', assignmentId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }

  /// All warnings addressed to one teacher, newest first.
  static Future<List<Map<String, dynamic>>> warningsForTeacher(
    String teacherId,
  ) async {
    if (teacherId.isEmpty) return [];
    try {
      final rows = await _client
          .from(warningsTable)
          .select('*')
          .eq('teacher_id', teacherId)
          .order('created_at', ascending: false)
          .limit(200);
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }

  /// Marks an assignment's warnings as read (teacher opened them).
  static Future<void> markWarningsRead({
    required String assignmentId,
    required String teacherId,
  }) async {
    if (assignmentId.isEmpty || teacherId.isEmpty) return;
    try {
      await _client.from(warningsTable).update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      }).eq('assignment_id', assignmentId).eq('teacher_id', teacherId).eq(
          'is_read', false);
    } catch (_) {}
  }

  // -- writes (Teacher) ---------------------------------------------------------------------

  /// Teacher changes their OWN assignment status. Teachers can never
  /// touch the task row itself. Completing notifies all admins.
  static Future<bool> updateStatus({
    required String assignmentId,
    required String teacherId,
    required String teacherName,
    required String taskId,
    required String taskTitle,
    required String status,
  }) async {
    final st = norm(status);
    if (!statuses.contains(st)) return false;
    try {
      final now = DateTime.now().toIso8601String();
      await _client.from(assignTable).update({
        'status': st,
        'completed_at': st == statusCompleted ? now : null,
        'updated_at': now,
      }).eq('id', assignmentId).eq('teacher_id', teacherId);
      // 🔔 Admins hear about completions (Working arrives via realtime).
      if (st == statusCompleted) {
        try {
          final who = teacherName.trim().isEmpty
              ? 'A teacher'
              : teacherName.trim();
          await NotificationService.publish(
            type: NotificationService.typeTeacherTask,
            title: 'Teacher Task Completed',
            message:
                '$who has completed: ${taskTitle.trim()}.',
            titleNe: 'शिक्षक कार्य पूरा भयो',
            messageNe:
                '$who ले पूरा गर्नुभयो: ${taskTitle.trim()}।',
            relatedId: 'teacher_task:$taskId:completed:$teacherId',
            destination:
                NotificationService.destTeacherTasksAdmin,
            audience: NotificationService.audienceAdmins,
          );
        } catch (_) {}
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// One assignment joined with its task: everything either list needs.
class TaskAssignment {
  final String id;
  final String taskId;
  final String teacherId;
  final String teacherName;
  final String status;
  final String completedAt;
  final String createdAt;
  final String title;
  final String description;
  final String taskType;
  final String section;
  final String dueDate;
  final String createdBy;

  const TaskAssignment({
    required this.id,
    required this.taskId,
    required this.teacherId,
    required this.teacherName,
    required this.status,
    required this.completedAt,
    required this.createdAt,
    required this.title,
    required this.description,
    required this.taskType,
    required this.section,
    required this.dueDate,
    required this.createdBy,
  });

  bool get isCompleted => status == TaskService.statusCompleted;
  bool get overdue => TaskService.isOverdue(status, dueDate);
  bool get dueSoon => TaskService.isDueSoon(status, dueDate);

  /// Display bucket: completed · overdue · working · not_completed.
  /// (Due Soon is an extra orange flag, not a separate bucket.)
  String get bucket {
    if (isCompleted) return TaskService.statusCompleted;
    if (overdue) return 'overdue';
    if (status == TaskService.statusWorking) {
      return TaskService.statusWorking;
    }
    return TaskService.statusNotCompleted;
  }
}
