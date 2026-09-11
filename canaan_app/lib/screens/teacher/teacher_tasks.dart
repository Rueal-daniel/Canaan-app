import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/task_service.dart';
import '../../widgets/animations.dart';
import 'task_detail.dart';

/// Teacher Dashboard → Quick Links → Teacher Tasks.
///
/// ONLY the logged-in teacher's own assignments (filtered by their
/// teacher_id at the query level). Live via Supabase Realtime.
class TeacherTasksPage extends StatefulWidget {
  final String teacherId;
  final String teacherName;
  final String section;
  const TeacherTasksPage({
    super.key,
    required this.teacherId,
    this.teacherName = '',
    this.section = '',
  });

  @override
  State<TeacherTasksPage> createState() => _TeacherTasksPageState();
}

class _TeacherTasksPageState extends State<TeacherTasksPage> {
  final _client = Supabase.instance.client;

  List<TaskAssignment> _all = [];
  bool _isLoading = true;
  String? _loadError;
  String _filter = 'all';
  // assignmentId -> unread warning count.
  Map<String, int> _warningUnread = {};
  final List<StreamSubscription> _subs = [];

  String get _sectionLabel {
    final s = TaskService.normalizeSection(widget.section);
    if (s.isEmpty) return '';
    if (s == 'sub-junior') return 'Sub Junior';
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  void initState() {
    super.initState();
    _fetch();
    _watch();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _watch() {
    void listen(String table) {
      try {
        _subs.add(_client
            .from(table)
            .stream(primaryKey: ['id'])
            .listen((_) {
              if (mounted) _fetch(silent: true);
            }));
      } catch (_) {}
    }

    listen(TaskService.tasksTable);
    listen(TaskService.assignTable);
    listen(TaskService.warningsTable);
  }

  Future<void> _fetch({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final results = await Future.wait([
        TaskService.fetchMine(widget.teacherId),
        TaskService.warningsForTeacher(widget.teacherId),
      ]);
      if (!mounted) return;
      final items = results[0] as List<TaskAssignment>;
      final warnings =
          results[1] as List<Map<String, dynamic>>;
      final unread = <String, int>{};
      for (final w in warnings) {
        if (w['is_read'] == true) continue;
        final aid = (w['assignment_id'] ?? '').toString();
        if (aid.isEmpty) continue;
        unread[aid] = (unread[aid] ?? 0) + 1;
      }
      setState(() {
        _all = items;
        _warningUnread = unread;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError = 'Could not load tasks. ($e)';
        });
      }
    }
  }

  List<TaskAssignment> get _visible {
    if (_filter == 'all') return _all;
    return _all.where((a) => a.bucket == _filter).toList();
  }

  int _count(String bucket) =>
      _all.where((a) => a.bucket == bucket).length;

  Future<void> _openDetail(TaskAssignment a) async {
    await Navigator.push(
      context,
      SlidePageRoute(
        page: TeacherTaskDetailPage(
          assignmentId: a.id,
          teacherId: widget.teacherId,
          teacherName: widget.teacherName,
        ),
      ),
    );
    if (mounted) _fetch(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2E1065), Color(0xFF6D28D9), Color(0xFFA78BFA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text('Teacher Tasks',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF7C3AED),
        onRefresh: () => _fetch(),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                    color: Color(0xFF7C3AED)))
            : _loadError != null
                ? _errorState()
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _headerCard(),
                        const SizedBox(height: 14),
                        _filterChips(),
                        const SizedBox(height: 12),
                        if (_visible.isEmpty)
                          _emptyState()
                        else
                          for (final a in _visible) _taskCard(a),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            Text(_loadError ?? '',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _fetch(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Retry',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCard() {
    final open = _all.where((a) => !a.isCompleted).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E1065), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.task_rounded,
              color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Tasks',
                    style: GoogleFonts.poppins(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  _all.isEmpty
                      ? 'No tasks assigned${_sectionLabel.isEmpty ? '' : ' · $_sectionLabel'}'
                      : '$open open · ${_count(TaskService.statusCompleted)} completed${_sectionLabel.isEmpty ? '' : ' · $_sectionLabel'}',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.9))),
              ]),
        ),
      ]),
    );
  }

  Widget _filterChips() {
    final options = [
      ('all', 'All (${_all.length})'),
      (TaskService.statusNotCompleted,
          'Not Completed (${_count(TaskService.statusNotCompleted)})'),
      (TaskService.statusWorking,
          'Working (${_count(TaskService.statusWorking)})'),
      (TaskService.statusCompleted,
          'Completed (${_count(TaskService.statusCompleted)})'),
      ('overdue', 'Overdue (${_all.where((a) => a.bucket == 'overdue').length})'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in options)
          ChoiceChip(
            label: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600)),
            selected: _filter == value,
            onSelected: (_) => setState(() => _filter = value),
            selectedColor:
                const Color(0xFF7C3AED).withValues(alpha: 0.15),
            backgroundColor: Colors.white,
            side: BorderSide(
              color: _filter == value
                  ? const Color(0xFF7C3AED)
                  : Colors.grey.shade300,
            ),
            labelStyle: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _filter == value
                  ? const Color(0xFF7C3AED)
                  : Colors.grey.shade600,
            ),
            showCheckmark: false,
          ),
      ],
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        Icon(Icons.task_outlined,
            size: 52, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(
          _filter == 'all'
              ? 'No tasks assigned yet.'
              : 'Nothing here.',
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151))),
        const SizedBox(height: 4),
        Text('New tasks from Admin appear here automatically.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 12.5, color: Colors.grey.shade500)),
      ]),
    );
  }

  Widget _taskCard(TaskAssignment a) {
    final color =
        TaskService.statusColor(a.status, overdue: a.overdue);
    final statusText = a.overdue
        ? 'Overdue'
        : TaskService.statusLabel(a.status);
    final unreadWarnings = _warningUnread[a.id] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(TaskService.typeIcon(a.taskType),
                      color: color, size: 24),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827))),
                      const SizedBox(height: 2),
                      Text(
                          a.taskType.isEmpty ? 'Other' : a.taskType,
                          style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.event_rounded,
                    size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      'Due: ${TaskService.prettyDate(a.dueDate)} · ${TaskService.dueLabel(a.dueDate)}',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: a.overdue
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF475569))),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          TaskService.statusIcon(a.status,
                              overdue: a.overdue),
                          size: 15,
                          color: color),
                      const SizedBox(width: 6),
                      Text('Status: $statusText',
                          style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: color)),
                    ],
                  ),
                ),
                const Spacer(),
                if (unreadWarnings > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                        '⚠️ $unreadWarnings Warning${unreadWarnings == 1 ? '' : 's'}',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFEF4444))),
                  ),
                if (a.dueSoon && !a.isCompleted)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('🟠 Due Soon',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFB45309))),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => _openDetail(a),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text('View Task',
                    style: GoogleFonts.poppins(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
    );
  }
}
